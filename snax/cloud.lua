local skynet = require 'skynet'
local snax = require 'skynet.snax'
local crypt = require 'skynet.crypt'
local mosq = require 'mosquitto'
local log = require 'utils.log'
local datacenter = require 'skynet.datacenter'
local ioe = require 'ioe'
local app_api = require 'app.api'
local cjson = require 'cjson.safe'
local cyclebuffer = require 'cyclebuffer'
local periodbuffer = require 'periodbuffer'
local uuid = require 'uuid'
local md5 = require 'md5'
local sha1 = require 'hashings.sha1'
local hmac = require 'hashings.hmac'
local cancelable_timeout = require 'cancelable_timeout'

--- Service running
local service_stop = false

--- Compress data using zlib
local zlib_loaded, zlib -- will be initialized in init(...)

--- Cloud/MQTT connection options
local mqtt_id = nil				--"UNKNOWN_ID"
local mqtt_host = nil			--"cloud.thingsroot.com"
local mqtt_port = nil			--1883
local mqtt_keepalive = nil		--300
local mqtt_client = nil			--- MQTT Client instance
local mqtt_client_last = nil	--- MQTT Client connection/disconnection time

--- Next reconnect timeout which will be multi by two until a max time
local mqtt_reconnect_timeout = 100

--- Whether using the async mode (which cause crashes for now -_-!)
local enable_async = false
--- Close connection flag in block mode
local close_connection = false
--- App devices data fire flag to prevent fire data when reconnected
local apps_devices_fired = false

--- Cloud options
local enable_data_upload = nil				--- Whether upload device data (boolean)
local enable_data_one_short_cancel = nil	--- Whether enable data upload in one short time (time)
local enable_stat_upload = nil				--- Whether upload device stat (boolean)
local enable_event_upload = nil				--- Whether upload event data (level in number)
local enable_comm_upload = nil				--- Whether upload communication data (time)
local enable_comm_upload_apps = {}			--- Whether upload communication data for specified application
local max_enable_comm_upload = 60 * 10		--- Max upload communication data period
local enable_log_upload = nil				--- Whether upload logs (time)
local max_enable_log_upload = 60 * 10		--- Max upload logs period

local api = nil					--- App API object to access devices
local cov = nil					--- COV helper
local cov_min_timer_gap = 10	--- COV min timer gap which will be set to period / 10 if upload period enabled
local pb = nil					--- Upload period buffer helper
local stat_pb = nil				--- Upload period buffer helper for stat data
local log_buffer = nil			--- Cycle buffer for logs
local event_buffer = nil		--- Cycle buffer for events
local comm_buffer = nil			--- Cycle buffer for communication data

--- Log function handler for mqtt library
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

--- Wild topics match to subscribe messages from cloud
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
		log.info('MSG.APP', topic, data, qos, retained)
		local args = assert(cjson.decode(data))
		local action = args.action or topic

		if action == 'install' then
			snax.self().post.app_install(args.id, args.data)
		end
		if action == 'uninstall' or action == 'remove' then
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
		if action == 'restart' then
			snax.self().post.app_restart(args.id, args.data)
		end
		if action == 'query_log' then
			snax.self().post.app_query_log(args.id, args.data)
		end
		if action == 'query_comm' then
			snax.self().post.app_query_comm(args.id, args.data)
		end
		if action == 'upload_comm' then
			snax.self().post.app_upload_comm(args.id, args.data)
		end
		if action == 'option' then
			snax.self().post.app_option(args.id, args.data)
		end
		if action == 'rename' then
			snax.self().post.app_rename(args.id, args.data)
		end
	end,
	sys = function(topic, data, qos, retained)
		log.info('MSG.SYS', topic, data, qos, retained)
		local args = assert(cjson.decode(data))
		local action = args.action or topic

		if action == 'enable/data' then
			snax.self().post.enable_data(args.id, tonumber(args.data) == 1)
		end
		if action == 'enable/data_one_short' then
			snax.self().post.enable_data_one_short(args.id, tonumber(args.data))
		end
		if action == 'enable/stat' then
			snax.self().post.enable_stat(args.id, tonumber(args.data) == 1)
		end
		if action == 'enable/log' then
			snax.self().post.enable_log(args.id, tonumber(args.data))
		end
		if action == 'enable/comm' then
			snax.self().post.enable_comm(args.id, tonumber(args.data))
		end
		if action == 'enable/beta' then
			snax.self().post.enable_beta(args.id, tonumber(args.data) == 1)
		end
		if action == 'enable/event' then
			snax.self().post.enable_event(args.id, tonumber(args.data))
		end
		if action == 'cloud_conf' then
			snax.self().post.set_cloud_conf(args.id, args.data)
		end
		if action == 'cfg/download' then
			snax.self().post.download_cfg(args.id, args.data)
		end
		if action == 'cfg/upload' then
			snax.self().post.upload_cfg(args.id, args.data)
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
		if action == 'batch_script' then
			snax.self().post.batch_script(args.id, args.data)
		end
		if action == 'restart' then
			snax.self().post.sys_quit(args.id, args.data)
		end
		if action == 'reboot' then
			snax.self().post.sys_reboot(args.id, args.data)
		end
		if action == 'data/flush' then
			snax.self().post.data_flush(args.id)
		end
		if action == "data/snapshot" then
			snax.self().post.fire_data_snapshot()
		end
		if action == "data/query" then
			snax.self().post.data_query(args.id, args.data)
		end
	end,
	output = function(topic, data, qos, retained)
		--log.trace('MSG.OUTPUT', topic, data, qos, retained)
		local oi = cjson.decode(data)
		if oi and oi.id then
			snax.self().post.output_to_device(oi.id, oi.data)
		end
	end,
	command = function(topic, data, qos, retained)
		local cmd = cjson.decode(data)
		if cmd and cmd.id then
			snax.self().post.command_to_device(cmd.id, cmd.data)
		end
	end,
}

local msg_callback = function(packet_id, topic, data, qos, retained)
	log.notice("msg_callback", packet_id, topic, data, qos, retained)
	local id, t, sub = topic:match('^([^/]+)/([^/]+)(.-)$')
	if id ~= mqtt_id and id ~= "ALL" then
		log.error("msg_callback recevied incorrect topic message")
		return
	end
	if id and t then
		local f = msg_handler[t]
		if f then
			if sub then
				sub = string.sub(sub, 2)
			end
			f(sub, data, qos, retained)
		else
			log.error("msg_callback cannot find handler", id, t)
		end
	end
end

local function connect_log_server(enable)
	local logger = snax.queryservice('logger')
	local obj = snax.self()
	if enable then
		logger.post.listen(obj.handle, obj.type)
	else
		logger.post.unlisten(obj.handle)
	end
end

local function mqtt_publish(topic, data, qos, retained)
	local value, err = cjson.encode(data)
	if not value then
		return nil, err
	end

	if not zlib_loaded then
		if mqtt_client then
			return mqtt_client:publish(topic, value, qos, retained)
		else
			return nil, "MQTT connection lost!"
		end
	else
		-- Compresss data
		local deflate = zlib.deflate()
		local deflated, eof, bytes_in, bytes_out = deflate(value, 'finish')
		if not deflated then
			return nil, eof, bytes_in, bytes_out
		end

		if mqtt_client then
			return mqtt_client:publish(topic.."_gz", deflated, qos, retained)
		else
			return nil, "MQTT connection lost!"
		end
	end
end

local function publish_data_no_pb(key, value, timestamp, quality)
	--log.trace('publish_data begin', mqtt_client, key, value)
	if not mqtt_client then
		return
	end

	--log.trace("Publish data", key, value, timestamp, quality)
	local val, err = cjson.encode({ key, timestamp, value, quality})
	if val then
		return mqtt_client:publish(mqtt_id.."/data", val, 1, false)
	else
		log.warning('Failed cjson encode', err)
		return nil, err
	end
end

local function publish_data(key, value, timestamp, quality)
	--log.trace('publish_data begin', mqtt_client, key, value)
	if not mqtt_client then
		return
	end

	--log.trace("Publish data", key, value, timestamp, quality)
	local val, err = cjson.encode({ key, timestamp, value, quality})
	if not val then
		log.warning('Failed cjson encode', err)
		return nil, err
	end
	if not pb then
		return mqtt_client:publish(mqtt_id.."/data", val, 1, false)
	else
		--log.trace('publish_data turn period buffer')
		pb:handle(key, timestamp, value, quality)
		return true
	end
end

local function publish_stat(key, value, timestamp, quality)
	--log.trace('publish_stat begin', mqtt_client, key, value)
	if not mqtt_client then
		return
	end

	--log.trace("Publish stat", key, value, timestamp)
	local val, err = cjson.encode({ key, timestamp, value, quality})
	if not val then
		log.warning('Failed cjson encode', err)
		return nil, err
	end

	if not stat_pb then
		return mqtt_client:publish(mqtt_id.."/stat", val, 1, false)
	else
		--log.trace('publish_stat turn period buffer')
		stat_pb:handle(key, timestamp, value, quality)
		return true
	end
end

local total_compressed = 0
local total_uncompressed = 0
local function publish_data_list_impl(val_list, topic)
	assert(val_list, topic)
	--log.trace('publish_data_list begin', mqtt_client, #val_list)
	if not mqtt_client or #val_list == 0 then
		return
	end

	local val, err = cjson.encode(val_list)
	if not val then
		log.error('JSON Encoding Error:', err)
	else
		--log.trace('Publish data in array and compress the json')
		local deflate = zlib.deflate()
		local deflated, eof, bytes_in, bytes_out = deflate(val, 'finish')
		if mqtt_client then
			total_compressed = total_compressed + bytes_out
			total_uncompressed = total_uncompressed + bytes_in
			local total_rate = (total_compressed/total_uncompressed) * 100
			local current_rate = (bytes_out/bytes_in) * 100
			log.trace('Count '..#val_list..' Original size '..bytes_in..' Compressed size '..bytes_out, current_rate, total_rate)

			local topic = mqtt_id.."/"..topic
			return mqtt_client:publish(topic, deflated, 1, false)
		end
	end
end

local publish_data_list = function(val_list)
	return publish_data_list_impl(val_list, 'data_gz')
end

local publish_stat_list = function(val_list)
	return publish_data_list_impl(val_list, 'stat_gz')
end

local function load_cov_conf()
	local enable_cov = datacenter.get("CLOUD", "COV") or true
	local default_ttl = 300 -- five minutes
	local ttl = datacenter.get("CLOUD", "COV_TTL") or default_ttl

	local cov_m = require 'cov'

	--- Device data cov stuff
	local opt = {}
	if not enable_cov and enable_data_upload then
		opt.disable = true
	else
		opt.ttl = ttl
		--- if data is not upload to our cloud, then take default ttl always.
		if enable_data_upload then
			opt.ttl = default_ttl
		end
	end
	cov = cov_m:new(opt)

	skynet.fork(function()
		while not service_stop do
			--- Trigger cov timer
			local gap = nil
			if zlib_loaded then
				local list = {}
				gap = cov:timer(skynet.time(), function(key, value, timestamp, quality) 
					list[#list+1] = {key, timestamp, value, quality}
				end)
				publish_data_list(list)
			else
				gap = cov:timer(skynet.time(), publish_data)
			end

			--- Make sure sleep not less than min gap
			if gap < cov_min_timer_gap then
				gap = cov_min_timer_gap
			end
			skynet.sleep(math.floor(gap * 100))
		end
	end)

	--- Stat data cov stuff
	local stat_cov_opt = {}
	if not enable_cov and enable_stat_upload then
		stat_cov_opt.disable = true
	else
		stat_cov_opt.ttl = ttl
		--- if data is not upload to our cloud, then take default ttl always.
		if enable_stat_upload then
			stat_cov_opt.ttl = default_ttl
		end
	end
	stat_cov = cov_m:new(opt)

	skynet.fork(function()
		while not service_stop do
			--- Trigger cov timer
			local gap = nil
			if zlib_loaded then
				local list = {}
				gap = stat_cov:timer(skynet.time(), function(key, value, timestamp, quality)
					list[#list+1] = {key, timestamp, value, quality}
				end)
				publish_stat_list(list)
			else
				gap = stat_cov:timer(skynet.time(), publish_stat)
			end

			--- Make sure sleep not less than min gap
			if gap < cov_min_timer_gap then
				gap = cov_min_timer_gap
			end
			skynet.sleep(math.floor(gap * 100))
		end
	end)
end


local function load_pb_conf()
	if not zlib_loaded then
		return
	end

	local period = tonumber(datacenter.get("CLOUD", "DATA_UPLOAD_PERIOD")  or 1000)-- period in ms

	-- If data is not upload to our cloud, then take pre-defined period (60 seconds)
	if not enable_data_upload then
		period = 60 * 1000
	end

	log.notice('Loading period buffer, period:', period)
	if period >= 1000 then
		cov_min_timer_gap = math.floor(period / 10)

		pb = periodbuffer:new(period, math.floor((1024 * period) / 1000))
		pb:start(publish_data_list)
		stat_pb = periodbuffer:new(period, math.floor((1024 * period) / 1000))
		stat_pb:start(publish_stat_list)
	else
		if pb then
			pb:stop()
			pb = nil
		end
		if stat_pb then
			stat_pb:stop()
			stat_pb = nil
		end
	end
end

--
--[[
-- loading configruation from datacenter
--]]
local function load_conf()
	mqtt_id = ioe.id() --datacenter.get("CLOUD", "ID") or datacenter.wait("SYS", "ID")
	mqtt_host = datacenter.get("CLOUD", "HOST")
	mqtt_port = datacenter.get("CLOUD", "PORT")
	mqtt_keepalive = datacenter.get("CLOUD", "KEEPALIVE")
	mqtt_secret = datacenter.get("CLOUD", "SECRET")
	log.notice("MQTT:", mqtt_id, mqtt_host, mqtt_port, mqtt_keepalive)

	enable_data_upload = datacenter.get("CLOUD", "DATA_UPLOAD")
	enable_stat_upload = datacenter.get("CLOUD", "STAT_UPLOAD")
	enable_comm_upload = datacenter.get("CLOUD", "COMM_UPLOAD")
	enable_log_upload = datacenter.get("CLOUD", "LOG_UPLOAD")
	enable_event_upload = tonumber(datacenter.get("CLOUD", "EVENT_UPLOAD"))

	enable_comm_upload_apps = datacenter.get("CLOUD", "COMM_UPLOAD_APPS") or {}
	local changed = false
	for k,v in pairs(enable_comm_upload_apps) do
		if v < skynet.time() then
			enable_comm_upload_apps[k] = nil
			changed = true
		end
	end
	if changed then
		datacenter.set('CLOUD', 'COMM_UPLOAD_APPS', enable_comm_upload_apps)
	end

	load_pb_conf()
	load_cov_conf()
end

local function publish_comm(app, sn, dir, ts, content)
	if not mqtt_client then
		return
	end

	local key = mqtt_id.."/comm"
	local msg = { (sn or app).."/"..dir, ts, content }
	--log.trace('publish comm', key, table.concat(msg))

	if enable_comm_upload and ts < enable_comm_upload then
		return mqtt_client:publish(key, cjson.encode(msg), 1, false)
	end

	if enable_comm_upload_apps[app] and ts < enable_comm_upload_apps[app] then
		return mqtt_client:publish(key, cjson.encode(msg), 1, false)
	end

	return true
end

local function publish_log(ts, lvl, ...)
	if not mqtt_client then
		return
	end
	if (enable_log_upload and ts < enable_log_upload) then
		return mqtt_client:publish(mqtt_id.."/log", cjson.encode({lvl, ts, ...}), 1, false)
	end
	return true
end

local function publish_event(sn, level, type_, info, data, timestamp)
	local event = { level = level, ['type'] = type_, info = info, data = data }
	if mqtt_client then
		return mqtt_client:publish(mqtt_id.."/event", cjson.encode({sn, event, timestamp}), 1, false)
	else
		return false
	end
end

function load_buffers()
	comm_buffer = cyclebuffer:new(32, "COMM")
	log_buffer = cyclebuffer:new(128, "LOG")
	event_buffer = cyclebuffer:new(16, "EVENT")
	skynet.fork(function()
		while not service_stop do
			local gap = 100
			if mqtt_client then
				local r = comm_buffer:fire_all(publish_comm)
					and log_buffer:fire_all(publish_log)
					and event_buffer:fire_all(publish_event)
				if r then
					gap = 500
				else
					log.trace('buffers loop', comm_buffer:size(), log_buffer:size(), event_buffer:size())
				end
			end
			skynet.sleep(gap)
		end
	end)
end

--[[
-- Api Handler
--]]
local Handler = {
	on_comm = function(app, sn, dir, ts, ...)
		--local hex = crypt.hexencode(table.concat({...}, '\t'))
		--hex = string.gsub(hex, "%w%w", "%1 ")
		--log.trace('on_comm', app, sn, dir, ts, hex)
		local content = crypt.base64encode(table.concat({...}, '\t'))
		comm_buffer:handle(publish_comm, app, sn, dir, ts, content)
	end,
	on_stat = function(app, sn, stat, prop, value, timestamp)
		--print(app, sn, stat, prop, value, timestamp)
		if not enable_stat_upload then
			return
		end

		local key = table.concat({sn, stat, prop}, '/')
		local timestamp = timestamp or skynet.time()
		local quality = 0

		stat_cov:handle(publish_stat, key, value, timestamp, quality)
	end,
	on_event = function(app, sn, level, type_, info, data, timestamp)
		if not enable_event_upload or (tonumber(level) < enable_event_upload)  then
			return
		end
		event_buffer:handle(publish_event, sn, level, type_, info, data, timestamp)
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

		--- disable data upload from the very begining here.
		if not enable_data_upload and sn ~= mqtt_id then
			-- Skip data
			return
		end

		local key = table.concat({sn, input, prop}, '/')
		local timestamp = timestamp or skynet.time()
		local quality = quality or 0

		cov:handle(publish_data, key, value, timestamp, quality)
	end,
	on_input_em = function(app, sn, input, prop, value, timestamp, quality)
		log.trace('on_set_device_prop_em', app, sn, input, prop, value, timestamp, quality)
		if not enable_data_upload and sn ~= mqtt_id then
			-- Skip data
			return
		end

		local key = table.concat({sn, input, prop}, '/')
		local timestamp = timestamp or skynet.time()
		local quality = quality or 0

		--cov:handle(publish_data_no_pb, key, value, timestamp, quality)
		publish_data_no_pb(key, value, timestamp, quality)
	end
}

function response.ping()
	if mqtt_client then
		mqtt_client:publish(mqtt_id.."/app", "ping........", 1, true)
	end
	return "PONG"
end

local connect_proc = nil
local function start_reconnect()
	close_connection = true
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
		local id = "dev="..mqtt_id.."|time="..os.time()
		local pwd = hmac:new(sha1, mqtt_secret, id):hexdigest()
		client:login_set(id, pwd)
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
			-- Only fire apps and device once
			if not apps_devices_fired then
				log.trace("ON_CONNECT fire devices and apps")
				apps_devices_fired = true
				snax.self().post.fire_devices()
				snax.self().post.fire_apps()
				if pb then
					skynet.timeout(100, function() snax.self().post.data_flush() end)
				end
			end
		else
			log.warning("ON_CONNECT", success, rc, msg) 
			start_reconnect()
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg) 
		log.warning("ON_DISCONNECT", success, rc, msg) 
		if not enable_async and mqtt_client then
			mqtt_client_last = skynet.time()
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
			if client then
				client:loop(50, 1)
			else
				skynet.sleep(50)
			end
		end
		if client then
			client:disconnect()
			log.notice("Cloud Connection Closed!")
			client:destroy()
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
		client:destory()
		log.notice("Cloud Connection Closed!")
	else
		close_connection = true
	end
	return true
end

function response.reconnect()
	if mqtt_client then
		return nil, "Already connected!"
	end
	start_reconnect()
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

function response.set_conf(conf, reboot)
	datacenter.set("CLOUD", conf)
	if reboot then
		snax.self().post.sys_quit(args.id, args.data)
	end
	return true
end

function response.get_conf()
	return datacenter.get("CLOUD")
end

function response.get_status()
	return mqtt_client ~= nil, mqtt_client_last
end

function accept.enable_data(id, enable)
	if enable then
		if enable_data_one_short_cancel then
			enable_data_one_short_cancel()
			enable_data_one_short_cancel = nil
		end
	end

	enable_data_upload = enable
	datacenter.set("CLOUD", "DATA_UPLOAD", enable)
	if not enable then
		if cov then
			cov:clean() -- cleanup cov for remove buffered snapshot for all devices
		end
		log.debug("Cloud data upload disabled!", enable)
	else
		snax.self().post.fire_data_snapshot()
	end
	snax.self().post.action_result('sys', id, true, "Done")
end

function accept.enable_data_one_short(id, period)
	if not enable_data_one_short_cancel and enable_data_upload then
		if id then
			snax.self().post.action_result('sys', id, false, "Cloud data upload is already enabled!")
		end
		return
	end

	if enable_data_one_short_cancel then
		enable_data_one_short_cancel()
		enable_data_one_short_cancel = nil
	end

	enable_data_upload = true
	log.debug("Cloud data one-short upload enabled!")

	if id then
		--- only enable one short if no id
		snax.self().post.action_result('sys', id, true, "Done")
		snax.self().post.fire_data_snapshot()
	end

	local period = tonumber(period) or 300
	enable_data_one_short_cancel = cancelable_timeout(period * 100, function()
		enable_data_upload = false
		if cov then
			cov:clean() -- cleanup cov for remove buffered snapshot for all devices
		end
		log.debug("Cloud data one-short upload disabled!")
	end)
end

function accept.enable_stat(id, enable)
	enable_stat_upload = enable
	datacenter.set("CLOUD", "STAT_UPLOAD", enable)
	if not enable then
		if stat_cov then
			stat_cov:clean()
		end
		log.debug("Cloud stat data upload disabled!", enable)
	else
		snax.self().post.fire_stat_snapshot()
	end
	snax.self().post.action_result('sys', id, true, "Done")
end

function accept.enable_log(id, sec)
	local sec = tonumber(sec)
	if sec > max_enable_log_upload then
		local err = "Log upload period cannot be bigger than "..max_enable_log_upload
		snax.self().post.action_result('sys', id, false, err)
		return
	end

	if sec and sec > 0 then
		enable_log_upload = math.floor(skynet.time()) + sec
	else
		enable_log_upload = nil
	end
	datacenter.set("CLOUD", "LOG_UPLOAD", enable_log_upload)
	snax.self().post.action_result('sys', id, true, "Done")
end

function accept.enable_comm(id, sec)
	local sec = tonumber(sec)
	if sec > max_enable_comm_upload then
		local err = "Comm upload period cannot be bigger than "..max_enable_comm_upload
		snax.self().post.action_result('sys', id, false, err)
		return
	end

	if sec and sec > 0 then
		enable_comm_upload = math.floor(skynet.time()) + sec
	else
		enable_comm_upload = nil
	end
	datacenter.set("CLOUD", "COMM_UPLOAD", enable_comm_upload)
	snax.self().post.action_result('sys', id, true, "Done")
end

function accept.enable_beta(id, enable)
	if not enable then
		ioe.set_beta(false)
	else
		local r, err = skynet.call(".upgrader", "lua", "pkg_enable_beta")
		if r then
			log.warning("Using beta is enabled from cloud!")
			ioe.set_beta(true)
		else
			log.warning("Cannot enable beta", err)
			snax.self().post.action_result('sys', id, false, err)
			return
		end
	end
	snax.self().post.action_result('sys', id, true, "Done")
end

function accept.enable_event(id, level)
	enable_event_upload = math.floor(tonumber(level))
	datacenter.set('CLOUD', 'EVENT_UPLOAD', enable_event_upload)
	snax.self().post.action_result('sys', id, true, "Done")
end

function accept.set_cloud_conf(id, args)
	for k, v in pairs(args) do
		datacenter.set("CLOUD", string.upper(k), v)
	end
	snax.self().post.action_result('sys', id, true, "Done! System will be reboot to table those changes")
	snax.self().post.sys_quit(id, data)
end

function accept.download_cfg(id, args)
	local r, err = skynet.call(".cfg", "lua", "download", args.name, args.host)
	snax.self().post.action_result('sys', id, r, err or "Done")
end

function accept.upload_cfg(id, args)
	local r, err = skynet.call(".cfg", "lua", "upload", args.host)
	snax.self().post.action_result('sys', id, r, err or "Done")
end


---
-- When register to logger service, this is used to handle the log messages
--
function accept.log(ts, lvl, ...)
	log_buffer:handle(publish_log, ts, lvl, ...)
end

---
-- Fire data snapshot (skip peroid buffer if zlib loaded)
---
function accept.fire_data_snapshot()
	local now = skynet.time()
	if zlib_loaded then
		local val_list = {}
		cov:fire_snapshot(function(key, value, timestamp, quality)
			val_list[#val_list + 1] = {key, timestamp or now, value, quality or 0}
		end)
		publish_data_list(val_list)
	else
		cov:fire_snapshot(function(key, value, timestamp, quality)
			publish_data(key, value, timestamp or now, quality or 0)
		end)
	end
	snax.self().post.action_result('input', id, r, err or "Done")
end

---
-- Fire stat snapshot (skip peroid buffer if zlib loaded)
---
function accept.fire_stat_snapshot()
	local now = skynet.time()
	if zlib_loaded then
		local val_list = {}
		stat_cov:fire_snapshot(function(key, value, timestamp, quality)
			val_list[#val_list + 1] = {key, timestamp or now, value, quality or 0}
		end)
		publish_stat_list(val_list)
	else
		stat_cov:fire_snapshot(function(key, value, timestamp, quality)
			publish_stat(key, value, timestamp or now, quality or 0)
		end)
	end
end

local fire_device_timer = nil
function accept.fire_devices(timeout)
	local timeout = timeout or 50
	log.notice("Cloud fire devices, timeout", timeout)
	if fire_device_timer then
		return
	end
	fire_device_timer = function()
		local devs = datacenter.get('DEVICES')
		local r, err = mqtt_publish(mqtt_id.."/devices", devs, 1, true)
		if not r then
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
	local timeout = timeout or 50
	log.notice("Cloud fire applications, timeout", timeout)
	if fire_app_timer then
		return
	end
	fire_app_timer = function()
		if mqtt_client then
			snax.self().post.app_list()
		else
			-- If mqtt connection is offline, retry after five seconds.
			snax.self().post.fire_apps(500)
		end
	end
	skynet.timeout(timeout, function()
		if fire_app_timer then
			fire_app_timer()
			fire_app_timer = nil
		end
	end)
end

function accept.app_event(event, inst_name, ...)
	snax.self().post.fire_apps()
end

function accept.app_install(id, args)
	skynet.call(".upgrader", "lua", "install_app", id, args)
end

function accept.app_uninstall(id, args)
	skynet.call(".upgrader", "lua", "uninstall_app", id, args)
end

function accept.app_upgrade(id, args)
	skynet.call(".upgrader", "lua", "upgrade_app", id, args)
end

function accept.app_start(id, args)
	local inst = args.inst
	local conf = args.conf
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.start(inst, conf)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.app_stop(id, args)
	local inst = args.inst
	local reason = args.reason
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.stop(inst, reason)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.app_restart(id, args)
	local inst = args.inst
	local reason = args.reason
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.restart(inst, reason)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.app_conf(id, args)
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.set_conf(args.inst, args.conf)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.app_list(id, args)
	local apps, err = skynet.call(".upgrader", "lua", "list_app")
	-- Fire action result if id is not empty
	if id then
		snax.self().post.action_result('app', id, apps, err or "Done")
	end

	if apps then
		local appmgr = snax.queryservice('appmgr')
		local app_list = appmgr.req.list()
		local now_time = skynet.time()
		for k, v in pairs(apps) do
			local app = app_list[k]
			if app and app.inst then
				v.running = now_time
				if now_time - app.last > 5 then
					v.blocked = app.last
				end
			end
		end

		mqtt_publish(mqtt_id.."/apps", apps, 1, true)
	end	
end

function accept.app_query_log(id, args)
	local log_reader = require 'log_reader'
	local app = args.inst
	--[[
	local max_count = tonumber(args.max_count) or 60
	local log, err = log_reader.by_app(app, max_count) 
	]]--
	local buffer = snax.queryservice('buffer')
	local logs, err = buffer.req.get_log(app)
	snax.self().post.action_result('app', id, logs, err or "Done")
	if logs then
		for _, log in ipairs(logs) do
			if mqtt_client then
				mqtt_client:publish(mqtt_id.."/app_log", cjson.encode({name=app, log=log}), 1, false)
			end
			skynet.sleep(0)
		end
	end
end

function accept.app_query_comm(id, args)
	local log_reader = require 'log_reader'
	local app = args.inst
	local buffer = snax.queryservice('buffer')
	local comms, err = buffer.req.get_comm(app)
	snax.self().post.action_result('app', id, comms, err or "Done")
	if comms then
		for _, comm in ipairs(comms) do
			if mqtt_client then
				mqtt_client:publish(mqtt_id.."/app_comm", cjson.encode({name=app, comm=comm}), 1, false)
			end
			skynet.sleep(0)
		end
	end
end

function accept.app_upload_comm(id, args)
	local app = args.inst
	local sec = tonumber(args.sec)
	if not app then
		return snax.self().post.action_result('app', id, false, "Applicaiton instance missing!")
	end
	if sec and sec > 0 and sec < max_enable_comm_upload then
		enable_comm_upload_apps[app] = math.floor(skynet.time()) + sec
	else
		enable_comm_upload_apps[app] = nil
	end
	datacenter.set("CLOUD", "COMM_UPLOAD_APPS", enable_comm_upload_apps)
	snax.self().post.action_result('app', id, true, "Done")
end

function accept.app_option(id, args)
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.app_option(args.inst, args.option, args.value)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.app_rename(id, args)
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.app_rename(args.inst, args.new_name)
	snax.self().post.action_result('app', id, r, err or "Done")
end

function accept.sys_upgrade(id, args)
	skynet.call(".upgrader", "lua", "upgrade_core", id, args)
end

function accept.sys_upgrade_ack(id, args)
	skynet.call(".upgrader", "lua", "upgrade_core_ack", id, args)
end

function accept.ext_list(id, args)
	local exts, err = skynet.call(".ioe_ext", "lua", "list")
	snax.self().post.action_result('app', id, exts, err or "Done")
	if exts then
		mqtt_publish(mqtt_id.."/exts", exts, 1, true)
	end
end

function accept.ext_upgrade(id, args)
	skynet.call(".ioe_ext", "lua", "upgrade_ext", id, args)
end

function accept.batch_script(id, script)
	log.debug("Cloud batch script received", id, script)
	datacenter.set("BATCH", id, "script", script)
	local runner = skynet.newservice("run_batch", id)
	datacenter.set("BATCH", id, "inst", runner)
end

function accept.sys_quit(id, args)
	skynet.call(".upgrader", "lua", "system_quit", id, {})
end

function accept.sys_reboot(id, args)
	skynet.call(".upgrader", "lua", "system_reboot", id, {})
end

--- Flush buffered period data
function accept.data_flush(id)
	if pb then
		pb:fire_all()
	else
		--- If upload period is not enabled then fire snapshot?
		snax.self().post.fire_data_snapshot()
	end

	if id then
		snax.self().post.action_result('sys', id, true, "Done")
	end
end

---
-- Query specified device data
--
function accept.data_query(id, dev_sn)
	if not dev_sn then
		return snax.self().post.action_result('input', id, false, "Device sn is required!")
	end
	local dev, err = api:get_device(device)
	if not dev then
		return snax.self().post.action_result('input', id, false, err)
	end

	--- Enable data upload one short for one minute
	if not enable_data_upload then
		snax.self().post.enable_data_one_short(nil, 60)
	end

	--- let device object fires its all input data
	dev:flush_data()

	--- Flush period buffer
	snax.self().post.fire_data_snapshot()
	snax.self().post.action_result('sys', id, true, "Done")
end

---
-- Fire device output
function accept.output_to_device(id, info)
	local device = info.device
	if not device then
		log.warning("device is missing in data")
		return
	end
	local dev, err = api:get_device(device)
	if not dev then
		return snax.self().post.action_result('ouput', id, false, err)
	end
	if type(info.value) == 'table' then
		info.value = cjson.encode(info.value)
	end
	local r, err = dev:set_output_prop(info.output, info.prop or "value", info.value)
	snax.self().post.action_result('output', id, r, err or "Done")
end

---
-- Fire device command
function accept.command_to_device(id, cmd)
	local device = cmd.device
	if device then
		local dev, err = api:get_device(device)
		if not dev then
			return snax.self().post.action_result('command', id, false, err)
		end
		if type(cmd.param) == 'table' then
			cmd.param = cjson.encode(cmd.param)
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
	zlib_loaded, zlib = pcall(require, 'zlib')
	if not zlib_loaded then
		log.warning("Cannot load zlib module, data compressing cannot be performed on this device")
	end

	mqtt_client_last = skynet.time()
	mosq.init()

	load_conf()
	load_buffers()

	connect_log_server(true)

	skynet.fork(function()
		connect_proc() 
	end)
	skynet.fork(function()
		api = app_api:new('CLOUD')
		api:set_handler(Handler, true)

		local appmgr = snax.queryservice('appmgr')
		local obj = snax.self()
		appmgr.post.listen(obj.handle, obj.type)
	end)
end

function exit(...)
	local obj = snax.self()
	appmgr.post.unlisten(obj.handle, obj.type)

	if enable_data_one_short_cancel then
		enable_data_one_short_cancel()
		enable_data_one_short_cancel = nil
	end
	connect_log_server(false)
	fire_device_timer = nil
	fire_app_timer = nil
	mosq.cleanup()
end
