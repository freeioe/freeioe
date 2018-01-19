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
local mqtt_id = nil --"UNKNOWN_ID"
local mqtt_host = nil --"cloud.symid.com"
local mqtt_port = nil --1883
local mqtt_keepalive = nil --300
local mqtt_client = nil
local mqtt_client_last = nil

--- Next reconnect timeout
local mqtt_reconnect_timeout = 100

--- Whether using the async mode (which cause crashes for now -_-!)
local enable_async = false
local close_connection = false

--- Cloud options
local enable_data_upload = nil -- true
local enable_stat_upload = nil
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
			snax.self().post.app_list(args.id, args.data)
		end
		if action == 'conf' then
			snax.self().post.app_conf(args.id, args.data)
		end
		if action == 'start' then
			snax.self().post.app_start(args.id, args.data)
		end
		if action == 'stop' then
			snax.self().post.app_stop(args.id, args.data)
		end
		if action == 'query_log' then
			snax.self().post.app_query_log(args.id, args.data)
		end
	end,
	sys = function(topic, data, qos, retained)
		--log.trace('MSG.SYS', topic, data, qos, retained)
		local args = assert(cjson.decode(data))
		local action = args.action or topic

		if action == 'enable/data' then
			snax.self().post.enable_data(tonumber(args.data) == 1)
		end
		if action == 'enable/stat' then
			snax.self().post.enable_stat(tonumber(args.data) == 1)
		end
		if action == 'enable/log' then
			snax.self().post.enable_log(tonumber(args.data))
		end
		if action == 'enable/comm' then
			snax.self().post.enable_comm(tonumber(args.data))
		end
		if action == 'enable/beta' then
			snax.self().post.enable_beta(tonumber(args.data) == 1)
		end
		if action == 'conf' then
			local conf = args.data
			snax.self().post.set_conf(conf)
		end
		if action == 'upgrade' then
			snax.self().post.sys_upgrade(args.id, args.data)
		end
		if action == 'upgrade/ack' then
			snax.self().post.sys_upgrade_ack(args.id, args.data)
		end
		if action == 'ext/list' then
			snax.self().post.ext_list(args.id, args.data)
		end
		if action == 'ext/upgrade' then
			snax.self().post.ext_upgrade(args.id, args.data)
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
	log.notice("msg_callback", packet_id, topic, data, qos, retained)
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

local function publish_data(key, value, timestamp, quality)
	if mqtt_client and enable_data_upload then
		--log.trace("Publish data", key, value, timestamp, quality)

		local val = cjson.encode({ key, timestamp, value, quality}) or value
		return mqtt_client:publish(mqtt_id.."/data", val, 1, false)
	end
	if not enable_data_upload then
		local sn = string.match(key, '^([^/]+)/')
		if sn == mqtt_id then
			local val = cjson.encode({ key, timestamp, value, quality}) or value
			return mqtt_client:publish(mqtt_id.."/data", val, 1, false)
		end
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
			if enable_data_upload then
				local gap = cov:timer(skynet.time(), publish_data)
				skynet.sleep(gap * 100)
			end
		end
	end)
end

--
--[[
-- loading configruation from datacenter
--]]
local function load_conf()
	mqtt_id = datacenter.get("CLOUD", "ID")
	mqtt_host = datacenter.get("CLOUD", "HOST")
	mqtt_port = datacenter.get("CLOUD", "PORT")
	mqtt_keepalive = datacenter.get("CLOUD", "KEEPALIVE")
	enable_data_upload = datacenter.get("CLOUD", "DATA_UPLOAD")
	enable_stat_upload = datacenter.get("CLOUD", "STAT_UPLOAD")
	enable_comm_upload = datacenter.get("CLOUD", "COMM_UPLOAD")
	enable_log_upload = datacenter.get("CLOUD", "LOG_UPLOAD")

	load_cov_conf()
end

--[[
-- Api Handler
--]]
local comm_buffer = nil
local Handler = {
	on_comm = function(app, sn, dir, ts, ...)
		--local hex = crypt.hexencode(table.concat({...}, '\t'))
		--hex = string.gsub(hex, "%w%w", "%1 ")
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
	on_stat = function(app, sn, stat, prop, value, timestamp)
		--print(app, sn, stat, prop, value, timestamp)
		if mqtt_client and enable_stat_upload then
			local key = mqtt_id.."/stat"
			local msg = {
				sn.."/"..stat.."/"..prop, timestamp, value
			}
			return mqtt_client:publish(key, cjson.encode(msg), 1, false)
		end
	end,
	on_add_device = function(app, sn, props)
		log.trace('on_add_device', app, sn, props)
		snax.self().post.device_add(app, sn, props)
	end,
	on_del_device = function(app, sn)
		log.trace('on_del_device', app, sn)
		snax.self().post.device_del(app, sn)
	end,
	on_mod_device = function(app, sn, props)
		log.trace('on_mod_device', app, sn, props)
		snax.self().post.device_mod(app, sn, props)
	end,
	on_input = function(app, sn, input, prop, value, timestamp, quality)
		--log.trace('on_set_device_prop', app, sn, input, prop, value, timestamp, quality)
		--local key = table.concat({app, sn, intput, prop}, '/')
		local key = table.concat({sn, input, prop}, '/')
		local timestamp = timestamp or skynet.time()
		local quality = quality or 0

		cov:handle(publish_data, key, value, timestamp, quality)
	end,
}

function response.ping()
	if mqtt_client then
		mqtt_client:publish(mqtt_id.."/app", "ping........", 1, true)
	end
	return "PONG"
end

local connect_proc = nil
local function start_reconnect()
	mqtt_client = nil
	skynet.timeout(mqtt_reconnect_timeout, function() connect_proc() end)
	mqtt_reconnect_timeout = mqtt_reconnect_timeout * 2
	if mqtt_reconnect_timeout > 10 * 60 * 100 then
		mqtt_reconnect_timeout = 100
	end

end

connect_proc = function(clean_session, username, password)
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
			mqtt_client_last = skynet.time()
			for _, v in ipairs(wildtopics) do
				--client:subscribe("ALL/"..v, 1)
				client:subscribe(mqtt_id.."/"..v, 1)
			end
			mqtt_reconnect_timeout = 100
		else
			log.warning("ON_CONNECT", success, rc, msg) 
			start_reconnect()
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg) 
		log.warning("ON_DISCONNECT", success, rc, msg) 
		if not enable_async and mqtt_client then
			start_reconnect()
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
		local ts = 1
		while not r do
			r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
			if not r then
				log.error(string.format("Connect to broker %s:%d failed!", mqtt_host, mqtt_port), err)
				skynet.sleep(ts * 500)
				ts = ts * 2
				if ts >= 64 then
					client:destroy()
					skynet.timeout(100, function() connect_proc() end)
					-- We meet bug that if client reconnect to broker with lots of failures, it's socket will be broken. 
					-- So we will re-create the client
					return
				end
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
		"STAT_UPLOAD",
		"COV",
		"COV_TTL",
		"PKG_HOST_URL",
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

function response.set_conf(conf)
	datacenter.set("CLOUD", conf)
	snax.self().post.reconnect()
	return true
end

function response.get_conf()
	return datacenter.get("CLOUD")
end

function response.get_status()
	return mqtt_client ~= nil, mqtt_client_last
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

function accept.enable_stat(enable)
	enable_stat_upload = enable
	datacenter.set("CLOUD", "STAT_UPLOAD", enable)
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

function accept.enable_beta(enable)
	if not enable then
		datacenter.set('CLOUD', 'USING_BETA', false)
	else
		local r, err = skynet.call("UPGRADER", "lua", "pkg_enable_beta")
		if r then
			log.warning("Using beta is enabled from cloud!")
			datacenter.set('CLOUD', 'USING_BETA', true)
		else
			log.warning("Cannot enable beta", err)
		end
	end
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
			mqtt_client:publish(mqtt_id.."/data", val, 1, false)
		end
	end)
end

local fire_device_timer = nil
function accept.fire_devices(timeout)
	local timeout = timeout or 10
	if fire_device_timer then
		return
	end
	fire_device_timer = function()
		local value = cjson.encode(datacenter.get('DEVICES'))
		if mqtt_client then
			mqtt_client:publish(mqtt_id.."/devices", value, 1, true)
		else
			-- If mqtt connection is offline, retry after five seconds.
			snax.self().post.fire_devices(500)
		end
	end
	skynet.timeout(timeout, function()
		if fire_device_timer then
			fire_device_timer()
			fire_device_timer = nil
		end
	end)
end

local function clean_cov_by_device_sn(sn)
	if cov then
		local len = string.len(sn) + 1
		local msn = sn..'/'
		cov:clean_with_match(function(key)
			return key:sub(1, len) == msn
		end)
	end
end

function accept.device_add(app, sn, props)
	clean_cov_by_device_sn(sn)
	snax.self().post.fire_devices()
end

function accept.device_mod(app, sn, props)
	clean_cov_by_device_sn(sn)
	snax.self().post.fire_devices()
end

function accept.device_del(app, sn)
	clean_cov_by_device_sn(sn)
	snax.self().post.fire_devices(100)
end

-- Delay application list post
local fire_app_timer = nil
function accept.fire_apps(timeout)
	if fire_app_timer then
		return
	end
	fire_app_timer = function()
		snax.self().post.app_list()
	end
	-- Timeout 10 seconds
	skynet.timeout(timeout or 1000, function()
		if fire_app_timer then
			fire_app_timer()
			fire_app_timer = nil
		end
	end)
end

function accept.app_install(id, args)
	skynet.call("UPGRADER", "lua", "install_app", id, args)
	snax.self().post.fire_apps()
end

function accept.app_uninstall(id, args)
	skynet.call("UPGRADER", "lua", "uninstall_app", id, args)
	snax.self().post.fire_apps(100)
end

function accept.app_upgrade(id, args)
	skynet.call("UPGRADER", "lua", "upgrade_app", id, args)
	snax.self().post.fire_apps()
end

function accept.app_start(id, args)
	local inst = args.inst
	local conf = args.conf
	local appmgr = snax.uniqueservice('appmgr')
	local r, err = appmgr.req.start(inst, conf)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.app_stop(id, args)
	local inst = args.inst
	local reason = args.reason
	local appmgr = snax.uniqueservice('appmgr')
	local r, err = appmgr.req.stop(inst, reason)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.app_conf(id, args)
	local appmgr = snax.uniqueservice('appmgr')
	local r, err = appmgr.req.set_conf(args.inst, args.conf)
	snax.self().post.action_result('app', id, r, err or "Done")
	snax.self().post.fire_apps(100)
end

function accept.app_list(id, args)
	local r, err = skynet.call("UPGRADER", "lua", "list_app")
	snax.self().post.action_result('app', id, r, err or "Done")
	if r then
		if mqtt_client then
			mqtt_client:publish(mqtt_id.."/apps", cjson.encode(r), 1, true)
		end
	end	
end

function accept.app_query_log(id, args)
	local log_reader = require 'log_reader'
	local app = args.name
	local max_count = tonumber(args.max_count) or 60
	local log, err = log_reader.by_app(app, max_count) 
	snax.self().post.action_result('app', id, r, err or "Done")
	if log then
		if mqtt_client then
			mqtt_client:publish(mqtt_id.."/app_log", cjson.encode({name=app, log=log}), 1, false)
		end
	end
end

function accept.sys_upgrade(id, args)
	skynet.call("UPGRADER", "lua", "upgrade_core", id, args)
end

function accept.sys_upgrade_ack(id, args)
	skynet.call("UPGRADER", "lua", "upgrade_core_ack", id, args)
end

function accept.ext_list(id, args)
	local r, err = skynet.call("IOT_EXT", "lua", "list")
	snax.self().post.action_result('app', id, r, err or "Done")
	if r then
		if mqtt_client then
			mqtt_client:publish(mqtt_id.."/exts", cjson.encode(r), 1, true)
		end
	end
end

function accept.ext_upgrade(id, args)
	skynet.call("IOT_EXT", "lua", "upgrade_ext", id, args)
end

function accept.output_to_app(id, info)
	local device = info.device
	if not device then
		log.warning("device is missing in data")
		return
	end
	local dev, err = api:get_device(device)
	if not dev then
		return snax.self().post.action_result('command', id, false, err)
	end
	local r, err = dev:set_output_prop(info.output, info.prop or "value", info.value)
	snax.self().post.action_result('output', id, r, err or "Done")
end

function accept.command_to_app(id, cmd)
	local device = cmd.device
	if device then
		local dev, err = api:get_device(device)
		if not dev then
			return snax.self().post.action_result('command', id, false, err)
		end
		local r, err = dev:send_command(cmd.cmd, cmd.param)
		snax.self().post.action_result('command', id, r, err or "OK")
	end
end

function accept.action_result(action, id, result, message)
	local result = result and true or false
	if mqtt_client then
		local r = {
			id = id,
			result = result,
			message = message,
			timestamp = skynet.time(),
			timestamp_str = os.date(),
		}
		log.notice("action_result", action, id, result, message)
		mqtt_client:publish(mqtt_id.."/result/"..action, cjson.encode(r), 1, false)
	end
end

function init()
	mqtt_client_last = skynet.time()
	mosq.init()

	load_conf()
	log.notice("MQTT:", mqtt_id, mqtt_host, mqtt_port, mqtt_keepalive)

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
	fire_app_timer = nil
	mosq.cleanup()
end
