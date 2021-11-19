local mqtt_client = require 'mqtt.skynet.client'
local cov = require 'cov'
local periodbuffer = require 'buffer.period'
local filebuffer = require 'buffer.file'
local sysinfo = require 'utils.sysinfo'
local index_stack = require 'utils.index_stack'
local ioe = require 'ioe'
local base_app = require 'app.base'

----
-- Configuration:
-- client_id - MQTT client id (默认使用网关id)
-- username - 认证时使用的用户名
-- password - 认证时使用的密码
-- server - MQTT 服务器地址
-- port - MQTT服务器端口
-- enable_tls - MQTT with TLS
-- tls_cert - MQTT Server cert file
-- tls_insecure - MQTT ca insecure
-- tls_ca_path -- MQTT TLS CA path
-- tls_client_cert -- MQTT client cert
-- tls_client_key -- MQTT client key
--
-- period - 周期上送的周期时间 (默认60秒)
-- ttl - 变化传输的强制上传周期（数据不变，但是经过ttl的时间数据必须上传一次, 默认300秒)
-- float_threshold - 变化传输浮点数据变化的最小量值 (默认0.0000001)
-- data_upload_dpp - 数据上传单包最多的数据点数量(默认1024)
-- data_upload_buffer - 周期上送最多缓存数据点数量(默认10240)
-- enable_data_cache - 是否开启断线缓存(1开启，其他关闭)
-- cache_per_file - 断线缓存单文件数据点数量(默认4096) 1024 ~ 4096
-- data_cache_limit - 断线缓存文件数量上限 1~ 256 默认128
-- data_cache_fire_gap - 断线缓存上送时的包间隔时间默认 1000ms (1000 ~ nnnn)
--
-- Your handlers are:
-- pack_key [o] -- 用于打包: src_app:采集应用名称 sn:采集设备序列号 input: 输入项名称 prop: 属性名, return nil will skip data
-- on_publish_devices [o] -- 打包所有设备信息上送回调
-- on_publish_data -- 用于未开启PB时的但数据点回调 (key, value, timestamp, quality)
-- on_publish_data_list -- 用于开启PB后，打包上送 (list --成员为 [key, value, timestamp, quality]), 成功返回true
-- on_publish_cached_data_list [o] -- 用于开启断缓后，打包上送 同PB, 返回上送数据的个数
--
-- mqtt_auth [o] -- 用于更新认证信息
-- mqtt_will [o] -- Will message
-- on_mqtt_connect_ok [o] -- 用于MQTT连接成功回调
-- on_mqtt_message -- MQTT消息接收函数
-- on_mqtt_publish -- MQTT发布回调， qos=1,2
--
-- The function from this helper
-- connected -- 连接状态
-- connect -- 开启连接(应用启动会自动开启一次连接)
-- disconnect -- 断开连接
-- publish -- 发布MQTT消息
-- subscribe
-- unsubscribe
-- compress -- 压缩数据
-- decompress -- 解压数据
--

local app = base_app:subclass("FREEIOE_EX_APP_MQTT_BASE")

---
function app:initialize(name, sys, conf)
	base_app.initialize(self, name, sys, conf)

	-- COV and PB
	self._disable_cov = conf.disable_cov or false
	self._period = tonumber(conf.period) or 60 -- seconds
	self._ttl = tonumber(conf.ttl) or 300 --- seconds
	self._float_threshold = tonumber(conf.float_threshold) or 0.000001
	self._max_data_upload_dpp = tonumber(conf.data_upload_dpp) or 1024
	self._max_data_buffer = tonumber(conf.data_upload_buffer) or 10240
	self._enable_data_cache = tonumber(conf.enable_data_cache) == 1
	self._data_per_file = tonumber(conf.cache_per_file) or 4096
	self._data_per_file = self._data_per_file < 1024 and 1024 or self._data_per_file
	self._data_per_file = self._data_per_file > 4096 and 4096 or self._data_per_file
	self._data_max_count = tonumber(conf.data_cache_limit) or 128
	self._data_max_count = self._data_max_count > 256 and 256 or self._data_max_count
	self._data_cache_fire_gap = tonumber(conf.data_cache_fire_gap) or 1000 -- ms
	self._data_cache_fire_gap = self._data_cache_fire_gap < 1000 and 1000 or self._data_cache_fire_gap

	self._connecting = nil
	self._close_connection = nil
	self._mqtt_reconnect_timeout = 1000
	self._max_mqtt_reconnect_timeout = 512 * 1000 -- about 8.5 minutes

	self._zlib_loaded, self._zlib = pcall(require, 'zlib')

	self._total_compressed = 0
	self._total_uncompressed = 0

	self._safe_call = function(f, ...)
		local r, er, err = xpcall(f, debug.traceback, ...)
		if not r then
			self._log:warning('Code bug', er, err)
			return nil, er and tostring(er) or nil
		end
		return er, er and tostring(err) or nil
	end

	--- Force QOS when enable data_cache
	if not conf.qos and self._enable_data_cache then
		conf.qos = true
	end

	self._mqtt_opt = {
		client_id = conf.client_id or sys:id(),
		clean_session = conf.clean_session ~= nil and conf.clean_session == true or false,
		username = conf.username,
		password = conf.password,
		host = conf.server,
		port = conf.port,
		keep_alive = conf.keep_alive,
		version = conf.version,
		qos = conf.qos
	}
	if conf.enable_tls then
		self._mqtt_opt.tls = self:map_tls_option({
			protocol = conf.tls_protocol,
			insecure = conf.tls_insecure,
			ca_file = conf.tls_cert,
			ca_path = conf.tls_ca_path,
			cert = conf.tls_client_cert,
			key = conf.tls_client_key,
			passwd = conf.tls_client_key_passwd,
		})
	end
end

function app:connected()
	return self._mqtt_client ~= nil and self._mqtt_client:connected()
end

function app:publish(topic, data, qos, retained)
	if not self._mqtt_client then
		self._log:trace("MQTT not connected!")
		return nil, "MQTT not connected!"
	end

	return self._mqtt_client:publish(topic, data, qos, retained)
end

function app:subscribe(topic, qos)
	if not self._mqtt_client then
		return nil, "MQTT not connected!"
	end
	return self._mqtt_client:subscribe(topic, qos or 1)
end

function app:unsubscribe(topic)
	return self._mqtt_client:unsubscribe(topic)
end


function app:_calc_compress(bytes_in, bytes_out)
	self._total_compressed = self._total_compressed + bytes_out
	self._total_uncompressed = self._total_uncompressed + bytes_in
	local total_rate = (self._total_compressed/self._total_uncompressed) * 100
	local current_rate = (bytes_out/bytes_in) * 100
	self._log:trace('Compress original size '..bytes_in..' compressed size '..bytes_out, current_rate, total_rate)
end

function app:compress(data)
	local deflate = self._zlib.deflate()
	local deflated, eof, bytes_in, bytes_out = deflate(data, 'finish')
	self:_calc_compress(bytes_in, bytes_out) 
	return deflated, eof, bytes_in, bytes_out
end

function app:decompress(data)
	local inflate = self._zlib.inflate()
	local inflated, eof, bytes_in, bytes_out = inflate(data, "finish")
	return inflated, eof, bytes_in, bytes_out
end

function app:connect()
	if not self._mqtt_client then
		return self:_connect_proc()
	end
	return nil, "Already connected"
end

function app:disconnect()
	if self._mqtt_client then
		self._mqtt_client:disconnect()
		self._mqtt_client = nil
	end
	return true
end

function app:on_add_device(src_app, sn, props)
	return self:_fire_devices(1000)
end
		--- 处理设备对象删除消息
function app:on_del_device(src_app, sn)
	return self:_fire_devices(1000)
end

--- 处理设备对象修改消息
function app:on_mod_device(src_app, sn, props)
	return self:_fire_devices()
end

--- 处理COV时需要打包app, sn, input到key
function app:pack_key(app, sn, input, prop)
	return string.format("%s/%s/%s", sn, input, prop)
end

--[[
function app:on_mqtt_connect_ok()
end

function app:mqtt_auth()
end

function app:mqtt_will()
end
]]---

--- 处理设备输入项数值变更消息
function app:on_input(src_app, sn, input, prop, value, timestamp, quality)
	return self:_handle_input(src_app, sn, input, prop, value, timestamp, quality)
end

function app:on_input_em(src_app, sn, input, prop, value, timestamp, quality)
	if not self.on_publish_data_em then
		return
	end

	local key = self._safe_call(self.pack_key, self, src_app, sn, input, prop)
	if not key then
		return
	end
	return self._safe_call(self.on_publish_data_em, self, key, value, timestamp, quality)
end

function app:_start_reconnect()
	local client = self._mqtt_client
	self._mqtt_client = nil

	self._sys:fork(function()
		if client then
			client:disconnect()
		end
		self._connecting = true
		self:_connect_proc()
		self._connecting = false
	end)
end

function app:map_tls_option(opt)
	local sys = self._sys
	assert(sys)

	if opt.ca_file then
		opt.ca_file = sys:app_dir()..opt.ca_file
	end
	if opt.ca_path then
		opt.ca_path = sys:app_dir()..opt.ca_path
	end
	if opt.cert then
		opt.cert = sys:app_dir()..opt.cert
	end
	if opt.key then
		opt.key = sys:app_dir()..opt.key
	end
	return opt
end

function app:_connect_proc()
	local log = self._log
	local sys = self._sys

	local info, err = {}, nil
	if self.mqtt_auth then
		info, err = self:mqtt_auth()
		if not info then
			log:error("ON_MQTT_PREPARE failed", err)
			return self:_start_reconnect()
		end
	end

	local mqtt_opt = {
		client_id = info.client_id,
		username = info.username,
		password = info.password,
		host = info.host,
		port = info.port,
		clean_session = info.clean_session ~= nil and info.clean_session == true or false,
		keep_alive = info.keep_alive,
		version = info.version,
		qos = info.qos
	}
	if info.enable_tls then
		mqtt_opt.tls = self:map_tls_option({
			protocol = info.tls_protocol,
			insecure = info.tls_insecure,
			ca_file = info.tls_cert,
			ca_path = info.tls_ca_path,
			cert = info.tls_client_cert,
			key = info.tls_client_key,
			passwd = info.tls_client_key_passwd,
		})
	end

	if self.mqtt_will then
		local topic, msg, qos, retained = self:mqtt_will()
		if topic and msg then
			mqtt_opt.will = {
				topic = topic,
				payload = msg,
				qos = qos or 1,
				retain = retained ~= nil and retained or true
			}
		end
	end

	local option = setmetatable(mqtt_opt, { __index = self._mqtt_opt })

	-- 创建MQTT客户端实例
	log:info("MQTT Connect:", option.client_id, option.host, option.port, option.username, option.password)

	local client = mqtt_client:new(option, self._log)

	-- 注册回调函数
	client.on_mqtt_connect = function(client, success, rc, msg) 
		if success then
			log:notice("ON_CONNECT", success, rc, msg) 
			if self._mqtt_client ~= client then
				self._log:warning("There is one client already connected!")
				self._mqtt_client:disconnect()
				self._mqtt_client = client
			end
			self._mqtt_client_last = sys:time()
			self._mqtt_reconnect_timeout = 1000

			if self.on_mqtt_connect_ok then
				self._sys:fork(function()
					self._safe_call(self.on_mqtt_connect_ok, self)
				end)
			end

			self:_fire_devices(1000)
		end
	end

	client.on_mqtt_disconnect = function(success, rc, msg) 
		if not self._mqtt_client or self._mqtt_client == client then
			self._mqtt_client_last = sys:time()
		end
	end

	if self.on_mqtt_publish then
		client.on_mqtt_publish = function(client, packet_id)
			self._safe_call(self.on_mqtt_publish, self, packet_id)
		end
	end

	if self.on_mqtt_message then
		client.on_mqtt_message = function(client, packet_id, topic, data, qos, retained)
			--print(packet_id, topic, data, qos, retained)
			if self.on_mqtt_message then
				self._safe_call(self.on_mqtt_message, self, packet_id, topic, data, qos, retained)
			end
		end
	end

	self._mqtt_client = client

	return client:connect()
end

function app:_handle_input(src_app, sn, input, prop, value, timestamp, quality)
	local key = self._safe_call(self.pack_key, self, src_app, sn, input, prop)
	if not key then
		return
	end
	if self._cov then
		self._cov:handle(key, value, timestamp, quality)
	else
		if not self:connected() then
			return nil, "MQTT not connected"
		end
		return self._safe_call(self.on_publish_data, self, key, value, timestamp, quality)
	end
end

function app:_fire_devices(timeout)
	local timeout = timeout or 1000
	if not self.on_publish_devices or not self._mqtt_client then
		return
	end

	if self._fire_device_timer then
		return
	end

	self._fire_device_timer = function()
		local devs = self._api:list_devices() or {}
		if self._mqtt_client then
			self._safe_call(self.on_publish_devices, self, devs)
		end
	end

	self._sys:timeout(timeout, function()
		if self._fire_device_timer then
			self._fire_device_timer()
			self._fire_device_timer = nil
		end
	end)
end

function app:_handle_cov_data(...)
	--self._log:trace('_handle_cov_data', ...)
	local pb = self._pb
	if not pb then
		if not self:connected() then
			return nil, "MQTT not connected"
		end
		return self._safe_call(self.on_publish_data, self, ...)
	else
		pb:push(...)
		return true
	end
end

function app:_init_cov()
	if self._disable_cov then
		self._log:warning('COV is disabled')
		return
	end
	local cov_opt = {ttl=self._ttl, float_threshold = self._float_threshold}
	self._cov = cov:new(function(...)
		return self:_handle_cov_data(...)
	end, cov_opt)
	self._cov:start()
end

function app:_init_pb()
	if not self._zlib_loaded then
		return
	end

	if self._period < 1 then
		self._log:warning('Period buffer not enabled', self._period)
		return
	end

	local period = self._period * 1000 -- seconds to ms

	self._log:notice('Loading period buffer! Period:', period, self._max_data_buffer, self._max_data_upload_dpp)
	self._pb = periodbuffer:new(period, self._max_data_buffer, self._max_data_upload_dpp) 

	self._pb:start(function(...)
		if not self:connected() then
			return nil, "MQTT not connected"
		end
		return self._safe_call(self.on_publish_data_list, self, ...)
	end, function(...)
		if self._fb_file then
			self._data_cache_used = true
			self._fb_file:push(...)
		end
	end)
end

function app:_init_fb()
	if not self._enable_data_cache or self._fb_file then
		return
	end

	--- file buffer
	local cache_folder = sysinfo.data_dir().."/app_cache_"..self._name
	self._log:notice('Data caches folder:', cache_folder)

	log:notice('Data caches option:', 
	self._data_per_file, 
	self._data_max_count, 
	self._data_cache_fire_gap,
	self._max_data_upload_dpp)

	self._fb_file = filebuffer:new(cache_folder, data_per_file, data_max_count, max_data_upload_dpp)
	self._fb_file:start(function(...)
		-- Disable one data fire
		return false
	end, function(...) 
		if not self:connected() then
			return nil, "Not connected"
		end
		assert(self.on_publish_cached_data_list, "on_publish_cached_data_list missing!!")
		return self._safe_call(self.on_publish_cached_data_list, self, ...)
	end)
end

--- 应用启动函数
function app:on_start()
	assert(self.on_publish_data, "on_publish_data missing!!!")
	assert(self.on_publish_data_list, "on_publish_data_list missing!!!")

	-- initialize COV PB, FB
	self:_init_cov()
	self:_init_pb()
	self:_init_fb()

	self:connect()

	self._log:debug("MQTT Connector Started!")

	return true
end

--- 应用退出函数
function app:on_close(reason)
	self:disconnect()
	return true
end

--- 返回应用对象类
return app
