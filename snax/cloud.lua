local skynet = require 'skynet'
local snax = require 'skynet.snax'
local mosq = require 'mosquitto'
local log = require 'utils.log'
local coroutine = require 'skynet.coroutine'
local datacenter = require 'skynet.datacenter'
local app_api = require 'app.api'
local cjson = require 'cjson.safe'
local cyclebuffer = require 'cyclebuffer'

--- Connection options
local mqtt_id = "UNKNOWN.CLLIENT.ID"
local mqtt_host = "cloud.symgrid.cn"
local mqtt_port = 1883
local mqtt_keepalive = 300
local mqtt_timeout = 1 -- 1 seconds
local mqtt_client = nil

--- Whether using the async mode (which cause crashes for now -_-!)
local enable_async = false

--- Cloud options
local enable_data_upload = nil
local enable_comm_upload = nil
local enable_log_upload = nil

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
	"data/#",
}

--- MQTT Publish Message Handler
local msg_handler = {
	data = function(topic, data, qos, retained)
		--log.trace('MSG.DATA', topic, data, qos, retained)
	end,
	app = function(topic, data, qos, retained)
		log.trace('MSG.APP', topic, data, qos, retained)
		if topic == '/install' then
			local app = cjson.decode(data)
			snax.self().post.app_install(app)
		end
		if topic == '/uninstall' then
			local app = cjson.decode(data)
			snax.self().post.app_uninstall(app)
		end
		if topic == '/upgrade' then
			local app = cjson.decode(data)
			snax.self().post.app_upgrade(app)
		end
		if topic == '/list' then
			snax.self().post.app_list()
		end
	end,
	sys = function(topic, data, qos, retained)
		--log.trace('MSG.SYS', topic, data, qos, retained)
		if topic == '/enable/data' then
			snax.self().post.enable_data(tonumber(data) == 1)
		end
		if topic == '/enable/log' then
			snax.self().post.enable_log(tonumber(data) == 1)
		end
		if topic == '/enable/comm' then
			snax.self().post.enable_comm(tonumber(data) == 1)
		end
		if topic == '/conf' then
			local conf = cjson.decode(data)
			if conf then
				datacenter.set("CLOUD", "ID", conf.id)
				datacenter.set("CLOUD", "HOST", conf.host)
				datacenter.set("CLOUD", "PORT", conf.port)
				datacenter.set("CLOUD", "TIMEOUT", conf.timeout)
			end
			snax.self().post.reconnect()
		end
		if topic == '/upgrade' then
			local core = cjson.decode(data)
			snax.self().post.sys_upgrade(core)
		end
	end,
	output = function(topic, data, qos, retained)
		--log.trace('MSG.OUTPUT', topic, data, qos, retained)
	end,
	input = function(topic, data, qos, retained)
		if topic == "/snapshot" then
			snax.self().post.fire_data_snapshot()
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
			f(sub, data, qos, retained)
		end
	end
end

local function on_enable_log_upload(enable)
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

	local cov_m = require 'cov'
	local opt = {}
	if not enable_cov then
		opt.disable = true
	end

	cov = cov_m:new(opt)
end

--[[
-- loading configruation from datacenter
--]]
local function load_conf()
	mqtt_id = datacenter.get("CLOUD", "ID") or mqtt_id
	mqtt_host = datacenter.get("CLOUD", "HOST") or mqtt_host
	mqtt_port = datacenter.get("CLOUD", "PORT") or mqtt_port
	mqtt_timeout = datacenter.get("CLOUD", "TIMEOUT") or mqtt_timeout
	enable_data_upload = datacenter.get("CLOUD", "DATA_UPLOAD")
	enable_comm_upload = datacenter.get("CLOUD", "COMM_UPLOAD")
	enable_log_upload = datacenter.get("CLOUD", "LOG_UPLOAD")

	if enable_log_upload then
		on_enable_log_upload(enable_log_upload)
	end

	load_cov_conf()
end

--[[
-- Api Handler
--]]
local comm_buffer = nil
local Handler = {
	on_comm = function(app, dir, ...)
		log.trace('on_comm', app, dir, ...)
		--[[
		if mqtt_client and enable_comm_upload then
			mqtt_client:publish(mqtt_id.."/comm/"..app.."/"..dir, table.concat({...}, '\t'), 1, false)
		end
		]]--

		local id = mqtt_id
		if enable_comm_upload then
			comm_buffer:handle(function(app, dir, ...)
				if mqtt_client then
					mqtt_client:publish(id.."/comm/"..app.."/"..dir, table.concat({...}, '\t'), 1, false)
					return true
				end
			end, app, dir, ...)
		end
	end,
	on_add_device = function(...)
		log.trace('on_add_device', ...)
	end,
	on_del_device = function(...)
		log.trace('on_del_device', ...)
	end,
	on_mod_device = function(...)
		log.trace('on_mod_device', ...)
	end,
	on_set_device_prop = function(app, sn, prop, prop_type, value, timestamp, quality)
		--log.trace('on_set_device_prop', app, sn, prop, prop_type, value)
		local val = { timestamp or skynet.time(), value, quality or 0 }
		local key = table.concat({app, sn, prop, prop_type}, '/')

		cov:handle(key, value, function(key, value)
			if mqtt_client and enable_data_upload then
				log.trace("Publish data", key, value, timestamp, quality)
				local value = cjson.encode(val) or value
				mqtt_client:publish(mqtt_id.."/data/"..key, value, 1, true)
			end
		end)
	end,
}

function response.ping()
	if mqtt_client then
		mqtt_client:publish(mqtt_id.."/app", "ping........", 1, true)
	end
	return "PONG"
end

function response.connect(clean_session, username, password)
	local clean_session = clean_session or true
	local client = mosq.new(mqtt_id, clean_session)
	if username then
		client:login_set(username, password)
	end
	client.ON_CONNECT = function(success, rc, msg) 
		if success then
			log.notice("ON_CONNECT", success, rc, msg) 
			mqtt_client = client
			for _, v in ipairs(wildtopics) do
				client:subscribe("ALL/"..v, 1)
				client:subscribe(mqtt_id.."/"..v, 1)
			end
			if enable_data_upload then
				snax.self().post.fire_data_snapshot()
			end
		else
			snax.self().post.reconnect_inter()
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg) 
		log.warning("ON_DISCONNECT", success, rc, msg) 
		if not enable_async and mqtt_client then
			snax.self().post.reconnect_inter()
		end
	end

	--[[
	client.ON_PUBLISH = function(...) log.debug("ON_PUBLISH", ...) end
	client.ON_SUBSCRIBE = function(...) log.debug("ON_SUBSCRIBE", ...) end
	client.ON_UNSUBSCRIBE = function(...) log.debug("ON_UNSUBSCRIBE", ...) end
	--client.ON_LOG = function(...) log.debug("ON_LOG", ...) end
	]]--

	-- Do not have on_log callback it crashes
	--client.ON_LOG = log_callback
	client.ON_MESSAGE = msg_callback

	if enable_async then
		local r, err = client:connect_async(mqtt_host, mqtt_port, mqtt_keepalive)
		client:loop_start()

		-- If we do not sleep, we will got crash :-(
		skynet.sleep(10)
	else
		local r, err
		while not r do
			r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
			if not r then
				log.error("Connect to broker failed!", err)
				skynet.sleep(500)
			end
		end

		mqtt_client = client

	end

	api = app_api:new('CLOUD')
	api:set_handler(Handler, true)

	return true
end

function response.disconnect()
	local client = mqtt_client
	log.debug("Cloud Connection Closing!")

	mqtt_client = nil
	client:disconnect()
	if enable_async then
		client:loop_stop()
	end
	client:destroy()

	log.notice("Cloud Connection Closed!")
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

function response.gen_sn()
	local uuid = require 'uuid'
	return uuid.new()
end

function accept.enable_cov(enable)
	datacenter.set("CLOUD", "COV", enable)
	load_cov_conf()
end

function accept.enable_log(enable)
	enable_log_upload = enable
	datacenter.set("CLOUD", "LOG_UPLOAD", enable)
	on_enable_log_upload(enable)
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

function accept.enable_comm(enable)
	enable_comm_upload = enable
	datacenter.set("CLOUD", "COMM_UPLOAD", enable)
end

---
-- When register to logger service, this is used to handle the log messages
--
local log_buffer = nil
function accept.log(ts, lvl, ...)
	--[[
	if mqtt_client and enable_log_upload then
		mqtt_client:publish(mqtt_id.."/log/"..lvl, table.concat({ts, ...}, '\t'), 1, false)
	end
	]]--
	local id = mqtt_id
	if enable_log_upload then
		log_buffer:handle(function(ts, lvl, ...)
			if mqtt_client then
				mqtt_client:publish(id.."/log/"..lvl, table.concat({ts, ...}, '\t'), 1, false)
				return true
			end
		end, ts, lvl, ...)
	end
end

---
-- Disconnect and reconnect again to server
--
function accept.reconnect()
	snax.self().req.disconnect()
	snax.self().req.connect()
end

---
-- Used by disconnected event for reconnect
--
function accept.reconnect_inter()
	local client = mqtt_client
	if not client then
		return
	end

	mqtt_client = nil
	local r, err
	while not r do
		r, err = client:reconnect()
		if not r then
			log.error("Reconnect to broker failed!", err)
			skynet.sleep(500)
		end
	end
	mqtt_client = client
end

---
-- Fire data snapshot
---
function accept.fire_data_snapshot()
	cov:fire_snapshot(function(key, v)
		if mqtt_client then
			local value = cjson.encode({ skynet.time(), v, 0 })
			mqtt_client:publish(mqtt_id.."/data/"..key, value, 1, true)
		end
	end)
end

function accept.app_install(app)
	local r, err = skynet.call("UPGRADER", "lua", "install_app", app.name, app.version, app.inst)
	if not r then
		log.error("App Install Failed. Error: ", err)
	end
end

function accept.app_uninstall(app)
	local r, err = skynet.call("UPGRADER", "lua", "uninstall_app", app.inst)
	if not r then
		log.error("App Uninstall Failed. Error: ", err)
	end
end

function accept.app_upgrade(app)
	local r, err = skynet.call("UPGRADER", "lua", "upgrade_app", app.inst, app.version)
	if not r then
		log.error("App Upgrade Failed. Error: ", err)
	end
end

function accept.app_list()
	local r, err = skynet.call("UPGRADER", "lua", "list_app")
	if r then
		if mqtt_client then
			mqtt_client:publish(mqtt_id.."/app/installed", cjson.encode(r), 1, true)
		end
	end	
end

function accept.sys_upgrade(core)
	local r, err = skynet.call("UPGRADER", "lua", "upgrade_core", app.version)
	if not r then
		log.error("SYS Upgrade Failed. Error: ", err)
	end
end

function init()
	load_conf()
	log.debug("MQTT:", mqtt_id, mqtt_host, mqtt_port, mqtt_timeout)

	comm_buffer = cyclebuffer:new(100)
	log_buffer = cyclebuffer:new(100)

	mosq.init()

	--- Worker thread
	skynet.fork(function()
		while true do
			if mqtt_client then
				mqtt_client:loop(50, 1)
				skynet.sleep(0)
			else
				skynet.sleep(50)
			end
		end
	end)
end

function exit(...)
	mosq.cleanup()
end
