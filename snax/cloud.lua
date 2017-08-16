local skynet = require 'skynet'
local snax = require 'skynet.snax'
local crypt = require 'skynet.crypt'
local mosq = require 'mosquitto'
local log = require 'utils.log'
local datacenter = require 'skynet.datacenter'
local app_api = require 'app.api'
local cjson = require 'cjson.safe'
local cyclebuffer = require 'cyclebuffer'
local uuid = require 'uuid'
local md5 = require 'md5'

--- Connection options
local mqtt_id = "UNKNOWN.CLLIENT.ID"
local mqtt_host = "cloud.symgrid.cn"
local mqtt_port = 1883
local mqtt_keepalive = 300
local mqtt_timeout = 1 -- 1 seconds
local mqtt_client = nil

--- Whether using the async mode (which cause crashes for now -_-!)
local enable_async = false
local close_connection = false

--- Cloud options
local enable_data_upload = nil
local enable_comm_upload = nil
local max_enable_comm_upload = 60 * 10
local enable_log_upload = nil
local max_enable_log_upload = 60 * 10

local api = nil
local cov = nil

--- Log function handler
local log_func = nil
local null_log_print = function() end
local log_callback = function(level, ...)
	if not log_func then
		log_func = {}
		log_func[mosq.LOG_NONE] = log.trace
		log_func[mosq.LOG_INFO] = log.info
		log_func[mosq.LOG_NOTICE] = log.notice
		log_func[mosq.LOG_WARNING] = log.warning
		log_func[mosq.LOG_ERROR] = log.error
		log_func[mosq.LOG_DEBUG] = null_log_print
		--log_func[mosq.LOG_DEBUG] = log.debug
	end

	local func = log_func[level]
	if func then
		func(...)
	else
		print(level, ...)
	end
end

--- Wild topics match
local wildtopics = {
	"app/#",
	"sys/#",
	"output/#",
	"command/#",
}

--- MQTT Publish Message Handler
local msg_handler = {
	data = function(topic, data, qos, retained)
		--log.trace('MSG.DATA', topic, data, qos, retained)
	end,
	app = function(topic, data, qos, retained)
		--log.trace('MSG.APP', topic, data, qos, retained)
		local args = assert(cjson.decode(data))
		local action = args.action or topic

		if action == 'install' then
			snax.self().post.app_install(args.id, args.data)
		end
		if action == 'uninstall' then
			snax.self().post.app_uninstall(args.id, args.data)
		end
		if action == 'upgrade' then
			snax.self().post.app_upgrade(args.id, args.data)
		end
		if action == 'list' then
			snax.self().post.app_list()
		end
		if action == 'conf' then
			snax.self().post.app_conf(args.id, args.data)
		end
	end,
	sys = function(topic, data, qos, retained)
		--log.trace('MSG.SYS', topic, data, qos, retained)
		local args = assert(cjson.decode(data))
		local action = args.action or topic

		if action == 'enable/data' then
			snax.self().post.enable_data(tonumber(args.data) == 1)
		end
		if action == 'enable/log' then
			snax.self().post.enable_log(tonumber(args.data))
		end
		if action == 'enable/comm' then
			snax.self().post.enable_comm(tonumber(args.data))
		end
		if action == 'conf' then
			local conf = args.data
			datacenter.set("CLOUD", "ID", conf.id)
			datacenter.set("CLOUD", "HOST", conf.host)
			datacenter.set("CLOUD", "PORT", conf.port)
			datacenter.set("CLOUD", "TIMEOUT", conf.timeout)
			snax.self().post.reconnect()
		end
		if action == 'upgrade' then
			snax.self().post.sys_upgrade(args.id, args.data)
		end
		if action == 'upgrade/ack' then
			snax.self().post.sys_upgrade_ack(args.id, args.data)
		end
	end,
	output = function(topic, data, qos, retained)
		--log.trace('MSG.OUTPUT', topic, data, qos, retained)
		local oi = cjson.decode(data)
		if oi and oi.id then
			snax.self().post.output_to_app(oi.id, oi.data)
		end
	end,
	input = function(topic, data, qos, retained)
		local args = assert(cjson.decode(data))
		local action = args.action or topic
		if action == "snapshot" then
			snax.self().post.fire_data_snapshot()
		end
	end,
	command = function(topic, data, qos, retained)
		local cmd = cjson.decode(data)
		if cmd and cmd.id then
			snax.self().post.command_to_app(cmd.id, cmd.data)
		end
	end,
}

local msg_callback = function(packet_id, topic, data, qos, retained)
	log.debug("msg_callback", packet_id, topic, data, qos, retained)
	local id, t, sub = topic:match('^([^/]+)/([^/]+)(.-)$')
	if id ~= mqtt_id and id ~= "ALL" then
		return
	end
	if id and t then
		local f = msg_handler[t]
		if f then
			if sub then
				sub = string.sub(sub, 2)
			end
			f(sub, data, qos, retained)
		end
	end
end

local function connect_log_server(enable)
	local logger = snax.uniqueservice('logger')
	local obj = snax.self()
	if enable then
		logger.post.reg_snax(obj.handle, obj.type)
	else
		logger.post.unreg_snax(obj.handle)
	end
end

local function load_cov_conf()
	local enable_cov = datacenter.get("CLOUD", "COV") or true
	local ttl = datacenter.get("CLOUD", "COV_TTL") or 60 -- 60 seconds

	local cov_m = require 'cov'
	local opt = {}
	if not enable_cov then
		opt.disable = true
	else
		opt.ttl = ttl
	end

	cov = cov_m:new(opt)

	skynet.fork(function()
		while true do
			skynet.sleep(ttl)
			cov:timer(skynet.time())
		end
	end)
end

--[[
-- loading configruation from datacenter
--]]
local function load_conf()
	mqtt_id = datacenter.get("CLOUD", "ID") or os.getenv("IOT_SN") or mqtt_id
	mqtt_host = datacenter.get("CLOUD", "HOST") or mqtt_host
	mqtt_port = datacenter.get("CLOUD", "PORT") or mqtt_port
	mqtt_timeout = datacenter.get("CLOUD", "TIMEOUT") or mqtt_timeout
	enable_data_upload = datacenter.get("CLOUD", "DATA_UPLOAD")
	local now = os.time()
	enable_comm_upload = datacenter.get("CLOUD", "COMM_UPLOAD")
	if enable_comm_upload and enable_comm_upload < now then
		enable_comm_upload=  nil
		datacenter.set("CLOUD", "COMM_UPLOAD", nil)
	end	
	enable_log_upload = datacenter.get("CLOUD", "LOG_UPLOAD")
	if enable_log_upload and enable_log_upload < now then
		enable_log_upload=  nil
		datacenter.set("CLOUD", "LOG_UPLOAD", nil)
	end

	load_cov_conf()
end

--[[
-- Api Handler
--]]
local comm_buffer = nil
local Handler = {
	on_comm = function(app, sn, dir, ts, ...)
		local hex = crypt.hexencode(table.concat({...}, '\t'))
		hex = string.gsub(hex, "%w%w", "%1 ")
		--log.trace('on_comm', app, sn, dir, ts, hex)
		local id = mqtt_id
		local content = crypt.base64encode(table.concat({...}, '\t'))
		comm_buffer:handle(function(app, sn, dir, ts, content)
			if mqtt_client and (enable_comm_upload and ts < enable_comm_upload) then
				local key = id.."/comm"
				local msg = {
					(sn or app).."/"..dir, ts, content
				}
				--log.trace('publish comm', key, table.concat(msg))
				return mqtt_client:publish(key, cjson.encode(msg), 1, false)
			end
		end, app, sn, dir, ts, content)
	end,
	on_add_device = function(app, sn, props)
		log.trace('on_add_device', app, sn, props)
		snax.self().post.fire_devices()
	end,
	on_del_device = function(app, sn)
		log.trace('on_del_device', app, sn)
		snax.self().post.fire_devices()
	end,
	on_mod_device = function(app, sn, props)
		log.trace('on_mod_device', app, sn, props)
		snax.self().post.fire_devices()
	end,
	on_input = function(app, sn, prop, prop_type, value, timestamp, quality)
		--log.trace('on_set_device_prop', app, sn, prop, prop_type, value, timestamp, quality)
		--local key = table.concat({app, sn, prop, prop_type}, '/')
		local key = table.concat({sn, prop, prop_type}, '/')
		local timestamp = timestamp or skynet.time()
		local quality = quality or 0

		cov:handle(function(key, value, timestamp, quality)
			if mqtt_client and enable_data_upload then
				--log.trace("Publish data", key, value, timestamp, quality)

				local val = cjson.encode({ key, timestamp, value, quality}) or value
				mqtt_client:publish(mqtt_id.."/data", val, 1, true)
			end
		end, key, value, timestamp, quality)
	end,
}

function response.ping()
	if mqtt_client then
		mqtt_client:publish(mqtt_id.."/app", "ping........", 1, true)
	end
	return "PONG"
end

local function connect_proc(clean_session, username, password)
	local clean_session = clean_session or true
	local client = assert(mosq.new(mqtt_id, clean_session))
	client:version_set(mosq.PROTOCOL_V311)
	if username then
		client:login_set(username, password)
	else
		--client:login_set('root', 'root')
		local pwd = md5.sumhexa(mqtt_id..'ZGV2aWNlIGlkCg==')
		client:login_set(mqtt_id, pwd)
	end
	client.ON_CONNECT = function(success, rc, msg) 
		if success then
			log.notice("ON_CONNECT", success, rc, msg) 
			client:publish(mqtt_id.."/status", "ONLINE", 1, true)
			mqtt_client = client
			for _, v in ipairs(wildtopics) do
				--client:subscribe("ALL/"..v, 1)
				client:subscribe(mqtt_id.."/"..v, 1)
			end
		else
			mqtt_client = nil
			skynet.timeout(100, function() connect_proc() end)
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg) 
		log.warning("ON_DISCONNECT", success, rc, msg) 
		if not enable_async and mqtt_client then
			mqtt_client = nil
			skynet.timeout(100, function() connect_proc() end)
		end
	end

	client.ON_LOG = log_callback
	client.ON_MESSAGE = msg_callback

	client:will_set(mqtt_id.."/status", "OFFLINE", 1, true)

	if enable_async then
		local r, err = client:connect_async(mqtt_host, mqtt_port, mqtt_keepalive)
		client:loop_start()
	else
		close_connection = false
		local r, err
		while not r do
			r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
			if not r then
				log.error("Connect to broker failed!", err)
				skynet.sleep(500)
			end
		end

		mqtt_client = client

		--- Worker thread
		while mqtt_client and not close_connection do
			skynet.sleep(0)
			if mqtt_client then
				mqtt_client:loop(50, 1)
			else
				skynet.sleep(50)
			end
		end
		if mqtt_client then
			mqtt_client:disconnect()
			log.notice("Cloud Connection Closed!")
		end
	end
end

function response.disconnect()
	local client = mqtt_client
	log.debug("Cloud Connection Closing!")

	if enable_async then
		mqtt_client = nil
		client:disconnect()
		client:loop_stop()
		log.notice("Cloud Connection Closed!")
	else
		close_connection = true
	end
	return true
end

function response.list_cfg_keys()
	return {
		"ID",
		"HOST",
		"PORT",
		"TIMEOUT",
		"DATA_UPLOAD",
		"LOG_UPLOAD",
		"COMM_UPLOAD",
		"COV",
	}
end

function response.gen_sn(sid)
	-- Frappe autoname 
	--hashlib.sha224((txt or "") + repr(time.time()) + repr(random_string(8))).hexdigest()
	--
	local key = mqtt_id..(sid or uuid.new())
	return md5.sumhexa(key):sub(1, 10)
end

function response.get_id()
	return mqtt_id
end

function accept.enable_cov(enable)
	datacenter.set("CLOUD", "COV", enable)
	load_cov_conf()
end

function accept.enable_data(enable)
	enable_data_upload = enable
	datacenter.set("CLOUD", "DATA_UPLOAD", enable)
	if enable then
		log.debug("Cloud data enabled, fire snapshot")
		snax.self().post.fire_data_snapshot()
	else
		log.debug("Cloud data upload disabled!", enable)
	end
end

function accept.enable_log(sec)
	local sec = tonumber(sec)
	if sec and sec > 0 and sec < max_enable_log_upload then
		enable_log_upload = os.time() + sec
	else
		enable_log_upload = nil
	end
	datacenter.set("CLOUD", "LOG_UPLOAD", enable_log_upload)
end

function accept.enable_comm(sec)
	local sec = tonumber(sec)
	if sec and sec > 0 and sec < max_enable_comm_upload then
		enable_comm_upload = os.time() + sec
	else
		enable_comm_upload = nil
	end
	datacenter.set("CLOUD", "COMM_UPLOAD", enable_comm_upload)
end

---
-- When register to logger service, this is used to handle the log messages
--
local log_buffer = nil
function accept.log(ts, lvl, ...)
	local id = mqtt_id
	log_buffer:handle(function(ts, lvl, ...)
		if mqtt_client and (enable_log_upload and ts < enable_log_upload) then
			return mqtt_client:publish(id.."/log", cjson.encode({lvl, ts, ...}), 1, false)
		end
	end, ts, lvl, ...)
end

---
-- Fire data snapshot
---
function accept.fire_data_snapshot()
	local now = skynet.time()
	cov:fire_snapshot(function(key, value, timestamp, quality)
		if mqtt_client then
			local val = cjson.encode({ key, timestamp or now, value, quality or 0 })
			mqtt_client:publish(mqtt_id.."/data", val, 1, true)
		end
	end)
end

local fire_device_timer = nil
function accept.fire_devices()
	if fire_device_timer then
		return
	end
	fire_device_timer = function()
		if mqtt_client then
			local value = cjson.encode(datacenter.get('DEVICES'))
			mqtt_client:publish(mqtt_id.."/devices", value, 1, true)
		end
	end
	skynet.timeout(10, function()
		if fire_device_timer then
			fire_device_timer()
			fire_device_timer = nil
		end
	end)
end

function accept.app_install(id, args)
	skynet.call("UPGRADER", "lua", "install_app", id, args)
end

function accept.app_uninstall(id, args)
	skynet.call("UPGRADER", "lua", "uninstall_app", id, args)
end

function accept.app_upgrade(id, args)
	skynet.call("UPGRADER", "lua", "upgrade_app", id, args)
end

function accept.app_conf(id, args)
	local appmgr = snax.uniqueservice('appmgr')
	local r, err = appmgr.req.set_conf(args.inst, args.conf)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.app_list()
	local r, err = skynet.call("UPGRADER", "lua", "list_app")
	if r then
		if mqtt_client then
			mqtt_client:publish(mqtt_id.."/apps", cjson.encode(r), 1, true)
		end
	end	
end

function accept.sys_upgrade(id, args)
	skynet.call("UPGRADER", "lua", "upgrade_core", id, args)
end

function accept.sys_upgrade_ack(id, args)
	skynet.call("UPGRADER", "lua", "upgrade_ack", id, args)
end

function accept.output_to_app(id, info)
	local id = info.id
	local device = info.device
	local dev = api:get_device(device)
	local r, err = dev:set_output_prop(info.output, info.prop or "value", info.value)
	if r then
		snax.self().post.action_result('output', id, r, err or "Done")
	end
end

function accept.command_to_app(id, cmd)
	local device = cmd.device
	if device then
		local dev = api:get_device(device)
		local r, err = dev:send_command(cmd.cmd, cmd.param)
		snax.self().post.action_result('command', id, r, err or "OK")
	end
end

function accept.action_result(action, id, result, message)
	if mqtt_client then
		local r = {
			id = id,
			result = result,
			message = message,
			timestamp = skynet.time(),
			timestamp_str = os.date(),
		}
		mqtt_client:publish(mqtt_id.."/result/"..action, cjson.encode(r), 1, false)
	end
end

function init()
	mosq.init()

	load_conf()
	log.debug("MQTT:", mqtt_id, mqtt_host, mqtt_port, mqtt_timeout)

	comm_buffer = cyclebuffer:new(32, "COMM")
	log_buffer = cyclebuffer:new(128, "LOG")

	connect_log_server(true)

	local s = snax.self()
	skynet.call("UPGRADER", "lua", "bind_cloud", s.handle, s.type)

	skynet.fork(function()
		api = app_api:new('CLOUD')
		api:set_handler(Handler, true)
	end)
	skynet.timeout(10, function() connect_proc() end)
end

function exit(...)
	fire_device_timer = nil
	mosq.cleanup()
end
