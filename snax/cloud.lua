local skynet = require 'skynet'
local snax = require 'skynet.snax'
local crypt = require 'skynet.crypt'
local mosq = require 'mosquitto'
local log = require 'utils.log'
local datacenter = require 'skynet.datacenter'
local ioe = require 'ioe'
local app_api = require 'app.api'
local cjson = require 'cjson.safe'
local cyclebuffer = require 'buffer.cycle'
local periodbuffer = require 'buffer.period'
local filebuffer = require 'buffer.file'
local index_stack = require 'utils.index_stack'
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
local mqtt_secret = nil			--- MQTT secret
local mqtt_client = nil			--- MQTT Client instance
local mqtt_client_last = nil	--- MQTT Client connection/disconnection time
local mqtt_client_last_msg = nil	--- MQTT Client connection/disconnection error message
local qos_msg_buf = nil			--- MQTT QOS messages

--- Next reconnect timeout which will be multi by two until a max time
local mqtt_reconnect_timeout = 100
local max_mqtt_reconnect_timeout = 512 * 100 --- about 8.5 minutes

--- Close connection flag in block mode
local close_connection = nil
--- App devices data fire flag to prevent fire data when reconnected
local apps_devices_fired = false

--- Cloud options
local enable_data_upload = nil				--- Whether upload device data (boolean)
local data_upload_max_dpp = 1024			--- Max data upload data count per packet
local enable_data_one_short_cancel = nil	--- Whether enable data upload in one short time (time)
local enable_stat_upload = nil				--- Whether upload device stat (boolean)
local enable_event_upload = nil				--- Whether upload event data (level in number)
local enable_comm_upload = nil				--- Whether upload communication data (time)
local enable_comm_upload_apps = {}			--- Whether upload communication data for specified application
local max_enable_comm_upload = 60 * 10		--- Max upload communication data period
local enable_log_upload = nil				--- Whether upload logs (time)
local max_enable_log_upload = 60 * 10		--- Max upload logs period

local enable_device_action = nil			--- Enable fire device action sperately
--- This is not enabled here, as the cloud depends on the devices topic retained data

local api = nil					--- App API object to access devices
local cov = nil					--- COV helper
local stat_cov = nil			--- Stat COV helper
local pb = nil					--- Upload period buffer helper
local stat_pb = nil				--- Upload period buffer helper for stat data
local data_cache_fb = nil		--- file saving the dropped data
local cache_fire_freq = 1000	--- fire cached data frequency
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
local wildtopics = { "app/#", "sys/#", "output/#", "command/#" }

--- MQTT Publish Message Handler
local msg_handler = {
	--[[
	data = function(topic, data, qos, retained)
		--log.trace('::CLOUD:: Data message:', topic, data, qos, retained)
	end,
	]]--
	app = function(topic, data, qos, retained)
		log.trace('::CLOUD:: App control:', topic, data, qos, retained)
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
		log.trace('::CLOUD:: System control:', topic, data, qos, retained)
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
		if action == 'ext/auto_clean' then
			snax.self().post.ext_aut_clean(args.id, args.data)
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
			snax.self().post.fire_data_snapshot(args.id)
		end
		if action == "data/query" then
			snax.self().post.data_query(args.id, args.data)
		end
	end,
	output = function(topic, data, qos, retained)
		log.trace('::CLOUD:: Device output:', topic, data, qos, retained)
		local oi = cjson.decode(data)
		if oi and oi.id then
			snax.self().post.output_to_device(oi.id, oi.data)
		end
	end,
	command = function(topic, data, qos, retained)
		log.trace('::CLOUD:: Device command:', topic, data, qos, retained)
		local cmd = cjson.decode(data)
		if cmd and cmd.id then
			snax.self().post.command_to_device(cmd.id, cmd.data)
		end
	end,
}

---
-- MQTT Message Callback
--
local msg_callback = function(packet_id, topic, data, qos, retained)
	log.info("::CLOUD:: message:", packet_id, topic, data, qos, retained)
	local id, t, sub = topic:match('^([^/]+)/([^/]+)(.-)$')
	if id ~= mqtt_id and id ~= "ALL" then
		log.error("::CLOUD:: msg_callback recevied incorrect topic message")
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
			log.error("::CLOUD:: msg_callback cannot find handler", id, t)
		end
	end
end

--- Listen to logger service used to forward logs
local function connect_log_server(enable)
	local logger = snax.queryservice('logger')
	local obj = snax.self()
	if enable then
		logger.post.listen(obj.handle, obj.type)
		skynet.call(".logger", "lua", "listen", obj.handle, obj.type)
	else
		logger.post.unlisten(obj.handle)
		skynet.call(".logger", "lua", "unlisten", obj.handle)
	end
end

--[[
local function mqtt_client_publish(...)
	return mqtt_client:publish(...)
end
]]--

local function mqtt_client_publish(topic, data, qos, retained)
	local mid, err = mqtt_client:publish(topic, data, qos, retained)
	if qos == 1 and mid then
		qos_msg_buf:push(mid, topic, data, qos, retained)
	end
	return mid, err
end

local function mqtt_resend_qos_msg()
	skynet.fork(function()
		qos_msg_buf:fire_all(mqtt_client_publish, 10, true)
	end)
end

local total_compressed = 0
local total_uncompressed = 0
local total_count = 0
local MAX_BYTE_COUNT = 0xFFFFFFFF
local last_echo_rate = 0

local function echo_compress_rate()
	local total_rate = (total_compressed/total_uncompressed) * 100
	log.trace('::CLOUD:: Data Count '..total_count..' Raw size '..total_uncompressed..' Compressed size '..total_compressed..' Rate '..total_rate)
end

local function calc_compress(bytes_in, bytes_out, count)
	if total_uncompressed > MAX_BYTE_COUNT or total_compressed > MAX_BYTE_COUNT then
		total_uncompressed = 0
		total_compressed = 0
		total_count = 0
	end
	total_compressed = total_compressed + bytes_out
	total_uncompressed = total_uncompressed + bytes_in
	total_count = total_count + count

	if mqtt_client and skynet.now() - last_echo_rate >= 60 * 100 then
		echo_compress_rate()
		last_echo_rate = (skynet.now() // 100) * 100
	end
end

--- MQTT Publish (not for data) with zip if it has
local function mqtt_publish(topic, data, qos, retained)
	local topic = assert(topic, 'Topic is required!')
	if not mqtt_client then
		return nil, "MQTT connection lost!"
	end

	local value, err = cjson.encode(data)
	if not value then
		log.warning('::CLOUD:: cjson encode failure. error: ', err)
		return nil, err
	end

	if zlib_loaded then
		-- Compresss data
		local deflate = zlib.deflate()
		local deflated, eof, bytes_in, bytes_out = deflate(value, 'finish')
		if not deflated then
			log.warning('::CLOUD:: zlib deflate failed', eof, bytes_in, bytes_out)
			return nil, eof, bytes_in, bytes_out
		end
		calc_compress(bytes_in, bytes_out, 1)
		value = deflated
		topic = topic.."_gz"
	end
	return mqtt_client:publish(topic, value, qos, retained)
end

--- Publish data without push to period buffer (no zip compress either)
local function publish_data_no_pb(key, value, timestamp, quality)
	--log.trace("::CLOUD:: Publish data", key, value, timestamp, quality)
	assert(key)
	if not mqtt_client then
		return nil, "MQTT connection lost!"
	end

	local val, err = cjson.encode({ key, timestamp, value, quality})
	if not val then
		log.warning('::CLOUD:: cjson encode failure. error: ', err)
		return nil, err
	end

	return mqtt_client_publish(mqtt_id.."/data", val, 1, false)
end

--- Push data to period buffer or publish to MQTT dirtectly
-- in our server we using [key, timestamp, value, quality] as data order,
--   in our MQTT standard which timestamp value position swapped :-(
local function publish_data(key, value, timestamp, quality)
	if pb then
		--log.trace('::CLOUD:: publish_data turn period buffer', key, value, timestamp, quality)
		pb:push(key, timestamp, value, quality)
		return true
	else
		--log.trace('::CLOUD:: publish_data', key, value, timestamp)
		return publish_data_no_pb(key, value, timestamp, quality)
	end
end

--- Push stat data to period buffer or publish to MQTT dirtectly
local function publish_stat(key, value, timestamp, quality)
	--log.trace('::CLOUD:: publish_stat begin', mqtt_client, key, value)
	if not mqtt_client then
		return nil, "MQTT connection lost!"
	end

	if stat_pb then
		--log.trace('::CLOUD:: publish_stat turn period buffer')
		stat_pb:push(key, timestamp, value, quality)
		return true
	end

	--log.trace("::CLOUD:: Publish stat", key, value, timestamp)
	local val, err = cjson.encode({ key, timestamp, value, quality})
	if not val then
		log.warning('::CLOUD:: cjson encode failure. error: ', err)
		return nil, err
	end

	return mqtt_client:publish(mqtt_id.."/stat", val, 1, false)
end

--- The implementation for publish data in list (zip compressing required)
local function publish_data_list_impl(val_list, topic)
	assert(val_list, topic)
	local val_count = #val_list
	--log.trace('::CLOUD:: publish_data_list begin', mqtt_id..'/'..topic, #val_list)
	if not mqtt_client or val_count == 0 then
		return nil, val_count == 0 and "Empty data list" or "MQTT connection lost!"
	end

	local val, err = cjson.encode(val_list)
	if not val then
		log.warning('::CLOUD:: cjson encode failure. error: ', err)
	else
		--log.trace('::CLOUD:: Publish data in array and compress the json for topic:', topic)
		local deflate = zlib.deflate()
		local deflated, eof, bytes_in, bytes_out = deflate(val, 'finish')
		if not deflated then
			log.warning('::CLOUD:: zlib deflate failed', eof, bytes_in, bytes_out)
			return nil, eof, bytes_in, bytes_out
		end

		if mqtt_client then
			calc_compress(bytes_in, bytes_out, val_count)
			--log.trace('::CLOUD:: publish_data_list', mqtt_id.."/"..topic, #val_list)
			return mqtt_client_publish(mqtt_id.."/"..topic, deflated, 1, false)
		end
	end
end

--- For data array publish
local publish_data_list = function(val_list)
	return publish_data_list_impl(val_list, 'data_gz')
end

local publish_cached_data_list = function(val_list)
	skynet.sleep(cache_fire_freq // 10) -- delay by gap
	if mqtt_client then
		log.debug('::CLOUD:: Uploading cached data! Count:', #val_list)
	end

	local r, err = publish_data_list_impl(val_list, 'cached_data_gz')
	if not r then
		return nil, err
	end

	return #val_list
end

--- For stat data array publish
local publish_stat_list = function(val_list)
	return publish_data_list_impl(val_list, 'stat_gz')
end

---
local warning_upload_period = 0
local push_to_data_cache = function(...)
	if data_cache_fb then
		if mqtt_client and skynet.time() > warning_upload_period  then
			warning_upload_period = skynet.time() + 5 * 60 * 100 --- 5 minutes
			log.warning('::CLOUD:: ***Make sure you have proper upload period if you read this***!!!')
		end
		data_cache_fb:push(...)
	end
end

---
-- Load and initialize the COV objects(data,stat)
--
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
		if not enable_data_upload then
			opt.ttl = default_ttl
		end
	end
	log.notice('::CLOUD:: COV option:', enable_cov, ttl, enable_data_upload)
	cov = cov_m:new(publish_data, opt)
	cov:start()

	--- Stat data cov stuff
	local stat_cov_opt = {}
	if not enable_cov and enable_stat_upload then
		stat_cov_opt.disable = true
	else
		stat_cov_opt.ttl = ttl
		--- if data is not upload to our cloud, then take default ttl always.
		if not enable_stat_upload then
			stat_cov_opt.ttl = default_ttl
		end
	end
	stat_cov = cov_m:new(publish_stat, stat_cov_opt)
	stat_cov:start()
end

--- Load file buffer objects
local function load_data_cache_conf()
	local enable_data_cache = datacenter.get("CLOUD", "DATA_CACHE")
	if not pb or not enable_data_cache then
		log.notice('::CLOUD:: Data cache disabled')
		return
	end

	if data_cache_fb then
		return
	end

	--- file buffer
	local sysinfo = require 'utils.sysinfo'
	local cache_folder = sysinfo.data_dir().."/cloud_cache"
	log.notice('::CLOUD:: Data cache folder:', cache_folder)

	-- should be more less than period_limit
	local per_file = tonumber(datacenter.get("CLOUD", "DATA_CACHE_PER_FILE") or 4096)
	-- about 240M in disk
	local limit = tonumber(datacenter.get("CLOUD", "DATA_CACHE_LIMIT") or 1024)
	-- Upload cached data one per gap time
	cache_fire_freq = tonumber(datacenter.get("CLOUD", "DATA_CACHE_FIRE_FREQ") or 1000)

	log.notice('::CLOUD:: Data cache option:', per_file, limit, cache_fire_freq, data_upload_max_dpp)

	data_cache_fb = filebuffer:new(cache_folder, per_file, limit, data_upload_max_dpp)
	data_cache_fb:start(function(...)
		-- Disable one data fire
		return false 
	end, publish_cached_data_list)
end

--- Load period buffer objects (data,stat)
local function load_pb_conf()
	if not zlib_loaded then
		return
	end

	--- Data Upload Period in ms
	local period = tonumber(datacenter.get("CLOUD", "DATA_UPLOAD_PERIOD") or 1000)
	--- Data Upload Buffer Max Size
	local period_limit = tonumber(datacenter.get("CLOUD", "DATA_UPLOAD_PERIOD_LIMIT") or 10240)

	log.notice('::CLOUD:: Period option:', period, period_limit, data_upload_max_dpp)
	if period >= 1000 then
		--- Period buffer enabled
		pb = periodbuffer:new(period, period_limit, data_upload_max_dpp)
		pb:start(publish_data_list, push_to_data_cache)

		--- there is no buffer for stat, so ten times for max buffer size
		stat_pb = periodbuffer:new(period, period_limit * 10, data_upload_max_dpp)
		stat_pb:start(publish_stat_list)
	else
		--- Period buffer disabled
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

----
-- loading configruation from datacenter
--
local function load_conf()
	mqtt_id = ioe.id() --datacenter.get("CLOUD", "ID") or datacenter.wait("SYS", "ID")
	mqtt_host = datacenter.get("CLOUD", "HOST")
	mqtt_port = datacenter.get("CLOUD", "PORT")
	mqtt_keepalive = datacenter.get("CLOUD", "KEEPALIVE")
	mqtt_secret = datacenter.get("CLOUD", "SECRET")

	log.notice("::CLOUD:: MQTT Connect:", mqtt_id, mqtt_host, mqtt_port, mqtt_keepalive)

	enable_data_upload = datacenter.get("CLOUD", "DATA_UPLOAD")
	enable_stat_upload = datacenter.get("CLOUD", "STAT_UPLOAD")
	enable_comm_upload = datacenter.get("CLOUD", "COMM_UPLOAD")
	enable_log_upload = datacenter.get("CLOUD", "LOG_UPLOAD")
	enable_event_upload = tonumber(datacenter.get("CLOUD", "EVENT_UPLOAD") or 99)
	data_upload_max_dpp = tonumber(datacenter.get("CLOUD", "DATA_UPLOAD_MAX_DPP") or 1024)

	--- For communication data applications list
	enable_comm_upload_apps = datacenter.get("CLOUD", "COMM_UPLOAD_APPS") or {}
	local changed = false --- This will help avoid file(cfg.json) writing caused by only table/cjson sorts
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
	load_data_cache_conf()
end

local function publish_comm(app_src, sn, dir, ts, content)
	if not mqtt_client then
		return nil, "MQTT connection lost!"
	end

	local topic = mqtt_id.."/comm"
	local msg = { (sn or app_src).."/"..dir, ts, content }
	--log.trace('::CLOUD:: publish comm', topic, table.concat(msg))

	if enable_comm_upload and ts < enable_comm_upload then
		return mqtt_client:publish(topic, cjson.encode(msg), 1, false)
	end

	if enable_comm_upload_apps[app_src] and ts < enable_comm_upload_apps[app_src] then
		return mqtt_client:publish(topic, cjson.encode(msg), 1, false)
	end

	return true
end

local function publish_log(ts, lvl, ...)
	if not mqtt_client then
		return nil, "MQTT connection lost!"
	end
	if not enable_log_upload or ts > enable_log_upload then
		return true
	end
	return mqtt_client:publish(mqtt_id.."/log", cjson.encode({lvl, ts, ...}), 1, false)
end

local function publish_event(app_src, sn, level, type_, info, data, timestamp)
	local event = { level = level, ['type'] = type_, info = info, data = data, app = app_src }
	if not mqtt_client then
		return nil, "MQTT connection lost!"
	end
	return mqtt_client:publish(mqtt_id.."/event", cjson.encode({sn, event, timestamp}), 1, false)
end

local function load_buffers()
	comm_buffer = cyclebuffer:new(publish_comm, 32)
	log_buffer = cyclebuffer:new(publish_log, 128)
	event_buffer = cyclebuffer:new(publish_event, 16)

	--- the run loop to fire those buffers
	skynet.fork(function()
		while not service_stop do
			local gap = 100
			if mqtt_client then
				local r = comm_buffer:fire_all()
					and log_buffer:fire_all()
					and event_buffer:fire_all()
				if r then
					gap = 500
				else
					--- If you see this trace
					log.trace('::CLOUD:: Buffers loop', comm_buffer:size(), log_buffer:size(), event_buffer:size())
					log.warning("::CLOUD:: Failed to fire comm or log or event")
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
		local content = crypt.base64encode(table.concat({...}, '\t'))
		--local hex = string.gsub(content, "%w%w", "%1 ")
		--log.trace('::CLOUD:: on_comm', app, sn, dir, ts, hex)
		comm_buffer:push(app, sn, dir, ts, content)
	end,
	on_stat = function(app, sn, stat, prop, value, timestamp)
		--log.trace('::CLOUD:: on_state', app, sn, stat, prop, value, timestamp)
		if not enable_stat_upload then
			return --- If not enable stat data upload will skip cov
		end

		local key = table.concat({sn, stat, prop}, '/')
		stat_cov:handle(key, value, timestamp or ioe.time(), quality or 0)
	end,
	on_event = function(app, sn, level, type_, info, data, timestamp)
		log.trace('::CLOUD:: on_event', app, sn, level, type_, info, timestamp, cjson.encode(data))
		if not enable_event_upload or (tonumber(level) < enable_event_upload)  then
			return --- If not enable event data upload will skip event buffer
		end
		event_buffer:push(app, sn, level, type_, info, data, timestamp)
	end,
	on_add_device = function(app, sn, props)
		log.trace('::CLOUD:: on_add_device', app, sn, props)
		snax.self().post.device_add(app, sn, props)
	end,
	on_del_device = function(app, sn)
		log.trace('::CLOUD:: on_del_device', app, sn)
		snax.self().post.device_del(app, sn)
	end,
	on_mod_device = function(app, sn, props)
		log.trace('::CLOUD:: on_mod_device', app, sn, props)
		snax.self().post.device_mod(app, sn, props)
	end,
	on_input = function(app, sn, input, prop, value, timestamp, quality)
		--log.trace('::CLOUD:: on_set_device_prop', app, sn, input, prop, value, timestamp, quality)
		--- disable data upload from the very begining here.
		if not enable_data_upload and sn ~= mqtt_id then
			return  -- Skip data
		end

		local key = table.concat({sn, input, prop}, '/')
		cov:handle(key, value, timestamp or ioe.time(), quality or 0)
	end,
	on_input_em = function(app, sn, input, prop, value, timestamp, quality)
		log.trace('::CLOUD:: on_set_device_prop_em', app, sn, input, prop, value, timestamp, quality)
		if not enable_data_upload and sn ~= mqtt_id then
			return -- Skip data
		end

		local key = table.concat({sn, input, prop}, '/')
		--cov:handle(key, value, timestamp, quality)
		publish_data_no_pb(key, value, timestamp or ioe.time(), quality or 0)
	end,
	on_output_result = function(app_src, priv, result, err)
		log.trace('::CLOUD:: on_output_result', app_src, priv, result, err)
		snax.self().post.action_result('output', priv, result, err)
	end,
	on_command_result = function(app_src, priv, result, err)
		log.trace('::CLOUD:: on_command_result', app_src, priv, result, err)
		snax.self().post.action_result('command', priv, result, err)
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
	if mqtt_client then
		log.error('::CLOUD:: ****Cannot start reconnection when client is there!****')
		return
	end

	log.notice('::CLOUD:: Start reconnect to cloud after '..(mqtt_reconnect_timeout/100)..' seconds')

	skynet.timeout(mqtt_reconnect_timeout, function() connect_proc() end)
	mqtt_reconnect_timeout = mqtt_reconnect_timeout * 2
	if mqtt_reconnect_timeout > max_mqtt_reconnect_timeout then
		mqtt_reconnect_timeout = 100
	end
end

---
-- Connection process function
--
connect_proc = function(clean_session, username, password)
	if mqtt_client then
		log.warning("::CLOUD:: There is one client exits!")
		return
	end

	local clean_session = clean_session ~= nil and clean_session or true
	local client = assert(mosq.new(mqtt_id, clean_session))
	local close_client = false -- set will close the connection work loop

	--- Set the protocol version
	client:version_set(mosq.PROTOCOL_V311)

	--- Set login by username/password
	if username then
		client:login_set(username, password)
	else
		local id = "dev="..mqtt_id.."|time="..os.time() --- id is device id and current time
		local pwd = hmac:new(sha1, mqtt_secret, id):hexdigest() --- hash the id as password
		client:login_set(id, pwd) --- Set the login
	end

	--- on connect result callback
	client.ON_CONNECT = function(success, rc, msg)
		mqtt_client_last_msg = msg
		if success then
			log.notice("::CLOUD:: ON_CONNECT", success, rc, msg)

			--- Check mqtt_client
			if mqtt_client then
				log.warning("::CLOUD:: There is one client exits!")
				close_client = true --- close current one
				return
			end

			--- Publish online status message
			local r, err = client:publish(mqtt_id.."/status", "ONLINE", 1, true)
			if not r then
				log.warning("::CLOUD:: Publish status failed", rc, err)
				close_client = true --- close current one
				return start_reconnect()
			end

			--- Set mqtt_client and last time
			mqtt_client = client
			local mqtt_last = mqtt_client_last or 0 -- remember last
			mqtt_client_last = skynet.time()
			--- Reset the reconnection timeout
			mqtt_reconnect_timeout = 100

			--- Subscribe topics
			for _, v in ipairs(wildtopics) do
				--client:subscribe("ALL/"..v, 1)
				client:subscribe(mqtt_id.."/"..v, 1)
			end

			-- Only fire apps and device once
			if not apps_devices_fired then
				log.info("::CLOUD:: ON_CONNECT upload devices and apps list")
				apps_devices_fired = true
				mqtt_last = 0  -- reset last
				snax.self().post.fire_devices()
				snax.self().post.fire_apps()
			end

			-- If we disconnected more than minute
			if mqtt_client_last - mqtt_last > 60 * 100 then
				--- Only flush data when period buffer enabled and period is bigger than 3 seconds
				if pb and pb:period() > 3000 then
					log.info("::CLOUD:: Flush all device data within three seconds!")
					skynet.timeout(300, function() snax.self().post.data_flush() end)
				end
			end

			-- Check Qos message
			mqtt_resend_qos_msg()

			log.notice("::CLOUD:: Connection is ready!!", client:socket())
		else
			log.warning("::CLOUD:: ON_CONNECT FAILED", success, rc, msg)
			-- There is an ON_DISCONNECT after this on_connect so we do not need to reconnect here
			--close_client = true --- close current one
			--start_reconnect()
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg)
		log.warning("::CLOUD:: ON_DISCONNECT", success, rc, msg)
		close_client = true --- close current one

		-- If client is current connection
		if not mqtt_client or mqtt_client == client then
			mqtt_client_last = skynet.time()
			mqtt_client = nil -- clear the client object as it wil cleaned by others
			mqtt_client_last_msg = msg -- record the error message

			-- If client is not asking to be closed then reconnect to cloud
			if close_connection == nil then
				start_reconnect()
			end
		end
	end
	client.ON_PUBLISH = function(mid)
		--log.trace("::CLOUD:: ON_PUBLISH", mid)
		qos_msg_buf:remove(mid)
	end

	--client.ON_LOG = log_callback
	client.ON_MESSAGE = msg_callback

	--- Tell mqtt backends that this device is online
	client:will_set(mqtt_id.."/status", "OFFLINE", 1, true)

	--- Loop until we connected to cloud or start the resonnection
	local r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
	local ts = 100
	while not r do
		log.error(string.format("::CLOUD:: Connect to broker %s:%d failed!", mqtt_host, mqtt_port), err)

		ts = ts * 2
		skynet.sleep(ts)

		--- Reach max reconnect timeout then destroy current client
		if ts > max_mqtt_reconnect_timeout then
			log.error("::CLOUD:: Destroy client and reconnect!")
			client:destroy()  -- destroy client
			mqtt_reconnect_timeout = 100 -- reset the reconnect timeout
			return start_reconnect()
		end

		-- r, err = client:reconnect()
		r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
	end

	--- Worker thread
	while client and not close_client and close_connection == nil do
		skynet.sleep(0)
		if client then
			client:loop(50, 1)
		else
			skynet.sleep(50)
		end
	end

	--- disconnect client and destory it
	client:disconnect()
	log.notice("::CLOUD:: Connection closed!")
	client:destroy()
	log.notice("::CLOUD:: Connection destroyed!")

	--- wakeup close connection waitor
	if close_connection then
		skynet.wakeup(close_connection)
	end
	--- Done here!!
end

function response.disconnect()
	log.notice("::CLOUD:: Try to close connection!")

	if close_connection ~= nil then
		log.notice("::CLOUD:: Connection is closing!")
		return nil, "Connection is closing!"
	end
	close_connection = {}
	skynet.wait(close_connection)
	close_connection = nil

	log.notice("::CLOUD:: Connection closed!")
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

--[[
function response.set_conf(conf, reboot)
	datacenter.set("CLOUD", conf)
	if reboot then
		snax.self().post.sys_quit(args.id, args.data)
	end
	return true
end
]]--

function response.get_conf()
	return datacenter.get("CLOUD")
end

function response.get_status()
	return mqtt_client ~= nil, mqtt_client_last, mqtt_client_last_msg
end

--- Enable data upload
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
		log.debug("::CLOUD:: data upload disabled!", enable)
	else
		snax.self().post.fire_data_snapshot()
	end
	snax.self().post.action_result('sys', id, true)
end

--- Enable data upload for a short time (specified by period in seconds, 300 by default)
function accept.enable_data_one_short(id, period)
	if not enable_data_one_short_cancel and enable_data_upload then
		if id then
			local err = "Cloud data upload is already enabled!"
			snax.self().post.action_result('sys', id, false, err)
		end
		return
	end

	if enable_data_one_short_cancel then
		enable_data_one_short_cancel()
		enable_data_one_short_cancel = nil
	end

	enable_data_upload = true
	log.debug("::CLOUD:: Data one-short upload enabled!")

	if id then
		--- only fire action result and data snapshot if has id
		snax.self().post.action_result('sys', id, true)
		snax.self().post.fire_data_snapshot()
	end

	local period = tonumber(period) or 300
	enable_data_one_short_cancel = cancelable_timeout(period * 100, function()
		enable_data_upload = false
		if cov then
			cov:clean() -- cleanup cov for remove buffered snapshot for all devices
		end
		log.debug("::CLOUD:: Data one-short upload disabled!")
	end)
end

function accept.enable_cache(id, enable)
	local enable = enable and true or false
	datacenter.set("CLOUD", "DATA_CACHE", enable)
	if not enable then
		log.debug("::CLOUD:: Data cache disabled!", enable)
		if data_cache_fb then
			data_cache_fb:stop()
			data_cache_fb = nil
		end
	else
		if not data_cache_fb then
			load_data_cache_conf()
		end
	end

	snax.self().post.action_result('sys', id, true)
end

function accept.enable_stat(id, enable)
	enable_stat_upload = enable and true or false
	datacenter.set("CLOUD", "STAT_UPLOAD", enable)
	if not enable then
		if stat_cov then
			stat_cov:clean()
		end
		log.debug("::CLOUD:: Stat data upload disabled!", enable)
	else
		snax.self().post.fire_stat_snapshot()
	end
	snax.self().post.action_result('sys', id, true)
end

function accept.enable_log(id, sec)
	local sec = tonumber(sec)
	if sec > max_enable_log_upload then
		local err = "Log upload period cannot be bigger than "..max_enable_log_upload
		snax.self().post.action_result('sys', id, false, err)
		return
	end
	--log.debug("::CLOUD:: Enable log upload for "..sec.." seconds")

	if sec and sec > 0 then
		enable_log_upload = math.floor(skynet.time()) + sec
	else
		enable_log_upload = nil
	end
	datacenter.set("CLOUD", "LOG_UPLOAD", enable_log_upload)
	snax.self().post.action_result('sys', id, true)
end

function accept.enable_comm(id, sec)
	local sec = tonumber(sec)
	if sec > max_enable_comm_upload then
		local err = "Comm upload period cannot be bigger than "..max_enable_comm_upload
		return snax.self().post.action_result('sys', id, false, err)
	end

	if sec and sec > 0 then
		enable_comm_upload = math.floor(skynet.time()) + sec
	else
		enable_comm_upload = nil
	end
	datacenter.set("CLOUD", "COMM_UPLOAD", enable_comm_upload)
	snax.self().post.action_result('sys', id, true)
end

function accept.enable_beta(id, enable)
	if not enable then
		log.warning("::CLOUD:: Using beta is disabled from cloud!")
		ioe.set_beta(false)
	else
		local r, err = skynet.call(".upgrader", "lua", "pkg_enable_beta")
		if r then
			log.warning("::CLOUD:: Using beta is enabled from cloud!")
			ioe.set_beta(true)
		else
			local msg = "Cannot enable beta. Error: "..err
			return snax.self().post.action_result('sys', id, false, msg)
		end
	end
	snax.self().post.action_result('sys', id, true)
end

function accept.enable_event(id, level)
	enable_event_upload = math.floor(tonumber(level))
	datacenter.set('CLOUD', 'EVENT_UPLOAD', enable_event_upload)
	snax.self().post.action_result('sys', id, true)
end

function accept.set_cloud_conf(id, args)
	for k, v in pairs(args) do
		datacenter.set("CLOUD", string.upper(k), v)
	end
	local msg = "Done! System will be reboot to table those changes"
	snax.self().post.action_result('sys', id, true, msg)
	snax.self().post.sys_quit(id, {})
end

function accept.download_cfg(id, args)
	local r, err = skynet.call(".cfg", "lua", "download", args.name, args.host)
	snax.self().post.action_result('sys', id, r, err)
end

function accept.upload_cfg(id, args)
	local r, err = skynet.call(".cfg", "lua", "upload", args.host)
	snax.self().post.action_result('sys', id, r, err)
end


---
-- When register to logger service, this is used to handle the log messages
--
function accept.log(ts, lvl, ...)
	log_buffer:push(ts, lvl, ...)
end

---
-- Fire data snapshot (skip peroid buffer if zlib loaded)
---
function accept.fire_data_snapshot(id)
	cov:fire_snapshot()
	if id then
		snax.self().post.action_result('input', id, true)
	end
end

---
-- Fire stat snapshot (skip peroid buffer if zlib loaded)
---
function accept.fire_stat_snapshot(id)
	stat_cov:fire_snapshot()
	if id then
		snax.self().post.action_result('input', id, true)
	end
end

local fire_device_timer = nil
function accept.fire_devices(timeout)
	if not mqtt_client then
		apps_devices_fired = nil -- wait untils the connection
		return
	end

	local timeout = timeout or 50
	log.notice("::CLOUD:: Upload devices list, timeout", timeout)
	if fire_device_timer then
		return
	end
	fire_device_timer = function()
		local devs = datacenter.get('DEVICES')
		local r, err = mqtt_publish(mqtt_id.."/devices", devs, 1, true)
		if not r then
			-- If mqtt connection is offline, retry after five seconds.
			log.notice("::CLOUD:: Upload devices list failed, retry after 5 seconds")
			snax.self().post.fire_devices(500)
		else
			log.notice("::CLOUD:: Upload devices list done!")
		end
	end

	if enable_device_action then
		fire_device_timer()
		fire_device_timer = nil
		return
	end

	skynet.timeout(timeout, function()
		if fire_device_timer then
			fire_device_timer()
			fire_device_timer = nil
		end
	end)
end

function accept.fire_device_action(action, sn, props)
	local data = {
		action = action,
		sn = sn,
		props = props
	}

	local fire_device = nil
	fire_device = function()
		local r, err = mqtt_publish(mqtt_id.."/device", data, 1, false)
		if not r then
			log.notice("::CLOUD:: Upload device event action failed, retry after 5 seconds")
			skynet.timeout(fire_device, 500)
		else
			log.notice("::CLOUD:: Upload device event action done!")
		end
	end
	fire_device()
end

local function clean_cov_by_device_sn(sn)
	local len = string.len(sn) + 1
	local msn = sn..'/'
	if cov then
		cov:clean_with_match(function(key)
			return key:sub(1, len) == msn
		end)
	end
	if stat_cov then
		stat_cov:clean_with_match(function(key)
			return key:sub(1, len) == msn
		end)
	end
end

function accept.device_add(app, sn, props)
	clean_cov_by_device_sn(sn)
	if enable_device_action then
		snax.self().post.fire_device_action('add', sn, props)
	else
		snax.self().post.fire_devices()
	end
end

function accept.device_mod(app, sn, props)
	clean_cov_by_device_sn(sn)
	if enable_device_action then
		snax.self().post.fire_device_action('mod', sn, props)
	else
		snax.self().post.fire_devices()
	end
end

function accept.device_del(app, sn)
	clean_cov_by_device_sn(sn)
	if enable_device_action then
		snax.self().post.fire_device_action('del', sn)
	else
		snax.self().post.fire_devices(100)
	end
end

-- Delay application list post
local fire_app_timer = nil
function accept.fire_apps(timeout)
	if not mqtt_client then
		apps_devices_fired = nil -- wait untils the connection
		return
	end

	local timeout = timeout or 50
	log.notice("::CLOUD:: Upload applications list, timeout", timeout)
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
	log.notice("::CLOUD:: Application event", event, inst_name, ...)
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
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.start(args.inst, args.conf)
	snax.self().post.action_result('app', id, r, err)
end

function accept.app_stop(id, args)
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.stop(args.inst, args.reason)
	snax.self().post.action_result('app', id, r, err)
end

function accept.app_restart(id, args)
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.restart(args.inst, args.reason)
	snax.self().post.action_result('app', id, r, err)
end

function accept.app_conf(id, args)
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.set_conf(args.inst, args.conf)
	snax.self().post.action_result('app', id, r, err)
end

function accept.app_list(id, args)
	local apps, err = skynet.call(".upgrader", "lua", "list_app")
	-- Fire action result if id is not empty
	if id then
		snax.self().post.action_result('app', id, apps, err)
	end

	if apps then
		local appmgr = snax.queryservice('appmgr')
		local app_list = appmgr.req.list()
		local now_time = ioe.time()
		for k, v in pairs(apps) do
			local app = app_list[k]
			if app and app.inst then
				v.running = now_time
				v.start = app.start
				v.last = app.last
				if now_time - app.last > 5 then
					v.blocked = app.last
				end
			end
		end

		mqtt_publish(mqtt_id.."/apps", apps, 1, true)
	end
end

function accept.app_query_log(id, args)
	local inst = args.inst
	--[[
	local log_reader = require 'utils.log_reader'
	local max_count = tonumber(args.max_count) or 60
	local log, err = log_reader.by_app(inst, max_count)
	]]--
	local buffer = snax.queryservice('buffer')
	local logs, err = buffer.req.get_log(inst)
	snax.self().post.action_result('app', id, logs, err)
	if logs then
		for _, content in ipairs(logs) do
			if mqtt_client then
				mqtt_client:publish(mqtt_id.."/app_log", cjson.encode({name=inst, log=content}), 1, false)
			end
			skynet.sleep(0)
		end
	end
end

function accept.app_query_comm(id, args)
	local inst = args.inst
	local buffer = snax.queryservice('buffer')
	local comms, err = buffer.req.get_comm(inst)
	snax.self().post.action_result('app', id, comms, err)
	if comms then
		for _, comm in ipairs(comms) do
			if mqtt_client then
				mqtt_client:publish(mqtt_id.."/app_comm", cjson.encode({name=inst, comm=comm}), 1, false)
			end
			skynet.sleep(0)
		end
	end
end

function accept.app_upload_comm(id, args)
	local inst = args.inst
	local sec = tonumber(args.sec)
	if not inst then
		return snax.self().post.action_result('app', id, false, "Applicaiton instance missing!")
	end
	if sec and sec > 0 and sec < max_enable_comm_upload then
		enable_comm_upload_apps[inst] = math.floor(skynet.time()) + sec
	else
		enable_comm_upload_apps[inst] = nil
	end
	datacenter.set("CLOUD", "COMM_UPLOAD_APPS", enable_comm_upload_apps)
	snax.self().post.action_result('app', id, true)
end

function accept.app_option(id, args)
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.app_option(args.inst, args.option, args.value)
	snax.self().post.action_result('app', id, r, err)
end

function accept.app_rename(id, args)
	local appmgr = snax.queryservice('appmgr')
	local r, err = appmgr.req.app_rename(args.inst, args.new_name)
	snax.self().post.action_result('app', id, r, err)
end

function accept.sys_upgrade(id, args)
	skynet.call(".upgrader", "lua", "upgrade_core", id, args)
end

function accept.sys_upgrade_ack(id, args)
	skynet.call(".upgrader", "lua", "upgrade_core_ack", id, args)
end

function accept.ext_list(id, args)
	local exts, err = skynet.call(".ioe_ext", "lua", "list")
	snax.self().post.action_result('app', id, exts, err)
	if exts then
		mqtt_publish(mqtt_id.."/exts", exts, 1, true)
	end
end

function accept.ext_upgrade(id, args)
	skynet.call(".ioe_ext", "lua", "upgrade_ext", id, args)
end

function accept.ext_auto_clean(id, args)
	skynet.call(".ioe_ext", "lua", "auto_clean", id, args)
end

function accept.batch_script(id, script)
	log.debug("::CLOUD:: Cloud batch script received", id, script)
	datacenter.set("BATCH", id, "script", script)
	local runner = skynet.newservice("run_batch", id)
	datacenter.set("BATCH", id, "inst", runner)
end

function accept.sys_quit(id, args)
	skynet.call(".cfg", "lua", "save")
	skynet.call(".upgrader", "lua", "system_quit", id, {})
end

function accept.sys_reboot(id, args)
	skynet.call(".cfg", "lua", "save")
	skynet.call(".upgrader", "lua", "system_reboot", id, {})
end

--- Flush buffered period data
function accept.data_flush(id)
	if pb then
		log.notice("::CLOUD:: Flush all data from period buffer to cloud!", id)
		pb:fire_all()
	else
		log.notice("::CLOUD:: Period buffer not enabled, nothing to flush!", id)
	end

	if id then
		snax.self().post.action_result('sys', id, true)
	end
end

---
-- Query specified device data
--
function accept.data_query(id, dev_sn)
	log.notice("::CLOUD:: Query data from device", dev_sn, id)
	if not dev_sn then
		return snax.self().post.action_result('input', id, false, "Device sn is required!")
	end
	local dev, err = api:get_device(dev_sn)
	if not dev then
		return snax.self().post.action_result('input', id, false, err)
	end

	--- Enable data upload one short for one minute
	if not enable_data_upload then
		snax.self().post.enable_data_one_short(nil, 60)
	end

	--- let device object fires its all input data to make sure cloud has it all data
	-- Using list_inputs instead of using flush_data, flush_data here will be slow by multicast stuff
	dev:list_inputs(function(input, prop, value, timestamp, quality)
		local key = table.concat({dev_sn, input, prop}, '/')
		cov:handle(key, value, timestamp or ioe.time(), quality or 0)
	end)

	--- Flush period buffer
	snax.self().post.data_flush(id)
end

---
-- Fire device output
function accept.output_to_device(id, info)
	local device = info.device
	if not device then
		return snax.self().post.action_result('ouput', id, false, "Device is missing in data")
	end

	local dev, err = api:get_device(device)
	if not dev then
		return snax.self().post.action_result('ouput', id, false, err)
	end

	if type(info.value) == 'table' then
		info.value = cjson.encode(info.value)
	end

	local r, err = dev:set_output_prop(info.output, info.prop or "value", info.value, ioe.time(), id)
	if not r then
		snax.self().post.action_result('output', id, false, err)
	end
end

---
-- Fire device command
function accept.command_to_device(id, cmd)
	local device = cmd.device
	if not device then
		return snax.self().post.action_result('command', id, false, "Device is missing in data")
	end

	local dev, err = api:get_device(device)
	if not dev then
		return snax.self().post.action_result('command', id, false, err)
	end

	if type(cmd.param) == 'string' then
		cmd.param = cjson.decode(cmd.param)
	end

	local r, err = dev:send_command(cmd.cmd, cmd.param, id)
	if not r then
		snax.self().post.action_result('command', id, false, err)
	end
end

---
-- Fire action resuult
function accept.action_result(action, id, result, message)
	local result = result and true or false
	local message = message or ( result and "Done" or "Error" )
	if mqtt_client then
		local r = {
			id = id,
			result = result,
			message = message,
			timestamp = ioe.time(),
			timestamp_str = os.date(),
		}
		if result then
			log.notice("::CLOUD:: Action result: ", action, id, result, message)
		else
			log.warning("::CLOUD:: Action result: ", action, id, result, message)
		end
		mqtt_client_publish(mqtt_id.."/result/"..action, cjson.encode(r), 1, false)
	end
end

function init()
	zlib_loaded, zlib = pcall(require, 'zlib')
	if not zlib_loaded then
		log.warning("::CLOUD:: Cannot load zlib module, data compressing disabled!!")
	end
	qos_msg_buf = index_stack:new(1024, function(...)
		log.error("::CLOUD:: MQTT QOS message droped!!!!")
	end)

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
		appmgr.post.listen(obj.handle, obj.type) -- Listen application event
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
