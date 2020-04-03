local mosq = require 'mosquitto'
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

	self._safe_call = function(f, ...)
		local r, er, err = xpcall(f, debug.traceback, ...)
		if not r then
			self._log:warning('Code bug', er, err)
			return nil, er and tostring(er) or nil
		end
		return er, er and tostring(err) or nil
	end

	self._mqtt_id = conf.client_id or sys:id()
	self._mqtt_username = conf.username
	self._mqtt_password = conf.password
	self._mqtt_host = conf.server or '127.0.0.1'
	self._mqtt_port = conf.port or 1883
	self._mqtt_enable_tls = conf.enable_tls
	self._mqtt_tls_insecure = conf.tls_insecure
	self._mqtt_tls_cert = conf.tls_cert
	self._mqtt_tls_ca_path = conf.tls_ca_path
	self._mqtt_client_cert = conf.client_cert
	self._mqtt_client_key = conf.client_key
	self._mqtt_clean_session = true

	-- COV and PB
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

	self._close_connection = nil
	self._mqtt_reconnect_timeout = 1000
	self._max_mqtt_reconnect_timeout = 512 * 1000 -- about 8.5 minutes

	self._zlib_loaded, self._zlib = pcall(require, 'zlib')

	self._total_compressed = 0
	self._total_uncompressed = 0

	self._qos_msg_buf = index_stack:new(1024, function(...)
		self._log:error("MQTT QOS message dropped!!")
	end)
end

function app:connected()
	return self._mqtt_client ~= nil
end

function app:publish(topic, data, qos, retained)
	local qos = qos or 0
	local retained = retained or false
	if not self._mqtt_client then
		self._log:trace("MQTT not connected!")
		return nil, "MQTT not connected!"
	end

	local mid, err = self._mqtt_client:publish(topic, data, qos, retained)
	--print(topic, mid, err)
	if qos == 1 and mid and not self._in_connection_ok_cb then
		self._qos_msg_buf:push(mid, topic, data, qos, retained)
	end
	return mid, err
end

function app:mqtt_resend_qos_msg()
	self._sys:fork(function()
		self._qos_msg_buf:fire_all(function(...)
			self:publish(...)
		end, 10, true)
	end)
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
	-- TODO: Check about connection before start proc

	self._sys:fork(function()
		self:_connect_proc()
	end)
end

function app:disconnect()
	if not self._mqtt_client then
		return
	end

	self._log:debug("Cloud Connection Closing!")
	self._close_connection = {}
	self._sys:wait(self._close_connection)
	self._close_connection = nil
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
	if self._mqtt_client then
		self._log:error('****Cannot start reconnection when client is there!****')
		return
	end

	self._log:notice('Start reconnect to cloud after '..(self._mqtt_reconnect_timeout/1000)..' seconds')

	self._sys:timeout(self._mqtt_reconnect_timeout, function() self:_connect_proc() end)
	self._mqtt_reconnect_timeout = self._mqtt_reconnect_timeout * 2
	if self._mqtt_reconnect_timeout > self._max_mqtt_reconnect_timeout then
		self._mqtt_reconnect_timeout = 1000
	end
end

function app:_connect_proc()
	local log = self._log
	local sys = self._sys

	local info, err = nil, nil
	if self.mqtt_auth then
		info, err = self:mqtt_auth()
		if not info then
			log:error("ON_MQTT_PREPARE failed", err)
			return self:_start_reconnect()
		end
	end

	local mqtt_id = info and info.client_id or self._mqtt_id
	local mqtt_host = info and info.host or self._mqtt_host
	local mqtt_port = info and info.port or self._mqtt_port
	local clean_session = info and info.clean_session or self._clean_session
	local username = info and info.username or self._mqtt_username
	local password = info and info.password or self._mqtt_password
	local enable_tls = info and info.enable_tls or self._mqtt_enable_tls
	local tls_insecure = info and info.tls_insecure or self._mqtt_tls_insecure
	local tls_cert = info and info.tls_cert or self._mqtt_tls_cert
	local tls_ca_path = info and info.tls_ca_path or self._mqtt_tls_ca_path
	local client_cert = info and info.client_cert or self._mqtt_client_cert
	local client_key = info and info.client_key or self._mqtt_client_key

	-- 创建MQTT客户端实例
	log:info("MQTT Connect:", mqtt_id, mqtt_host, mqtt_port, username, password)
	local client = assert(mosq.new(mqtt_id, clean_session))
	local close_client = false
	client:version_set(mosq.PROTOCOL_V311)
	if username and string.len(username) > 0 then
		client:login_set(username, password)
	end
	if enable_tls then
		if tls_insecure == true then
			log:warning("MQTT using insecure tls connection!")
			client:tls_insecure_set(true)
		end
		client_cert = client_cert and sys:app_dir()..client_cert or nil
		client_key = client_key and sys:app_dir()..client_key or nil
		tls_cert = tls_cert and sys:app_dir()..tls_cert or nil
		--print(tls_cert, tls_ca_path or 'nil', client_cert or 'nil', client_key or 'nil')
		local r, errno, err = client:tls_set(tls_cert, tls_ca_path, client_cert, client_key)
		if not r then
			log:error("TLS set error", errno, err)
		end
	end

	-- 注册回调函数
	client.ON_CONNECT = function(success, rc, msg) 
		if success then
			log:notice("ON_CONNECT", success, rc, msg) 
			if self._mqtt_client then
				self._log:warning("There is one client already connected!")
				close_client = true
				return
			end

			self._mqtt_client = client
			self._mqtt_client_last = sys:time()
			self._mqtt_reconnect_timeout = 1000

			if self.on_mqtt_connect_ok then
				self._sys:fork(function()
					self._safe_call(self.on_mqtt_connect_ok, self)
				end)
			end

			self:_fire_devices(1000)
			---
			self:mqtt_resend_qos_msg()
		else
			log:warning("ON_CONNECT FAILED", success, rc, msg) 
			-- ON_DISCONNECT will be called soon
			--close_client = true
			--self:_start_reconnect()
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg) 
		log:warning("ON_DISCONNECT", success, rc, msg) 
		close_client = true

		if not self._mqtt_client or self._mqtt_client == client then
			self._mqtt_client_last = sys:time()
			self._mqtt_client = nil
			if self._close_connection == nil then
				self:_start_reconnect()
			end
		end
	end
	client.ON_PUBLISH = function (mid)
		--print('on_publish', mid)
		self._qos_msg_buf:remove(mid)

		if self.on_mqtt_publish then
			self._sys:fork(function()
				self._safe_call(self.on_mqtt_publish, self, mid)
			end)
		end
	end
	--[[
	client.ON_LOG = function(...)
	end
	]]--
	client.ON_MESSAGE = function(packet_id, topic, data, qos, retained)
		--print(packet_id, topic, data, qos, retained)
		if self.on_mqtt_message then
			self._sys:fork(function()
				self._safe_call(self.on_mqtt_message, self, packet_id, topic, data, qos, retained)
			end)
		end
	end

	if self.mqtt_will then
		local topic, msg, qos, retained = self:mqtt_will()
		if topic and msg then
			client:will_set(topic, msg, qos or 1, retained == nil and true or false)
		end
	end

	log:info('MQTT Connectting...')
	local r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
	local ts = 1000
	while not r do
		log:error(string.format("Connect to broker %s:%d failed!", mqtt_host, mqtt_port), err)
		ts = ts * 2
		self._sys:sleep(ts)

		if ts > self._max_mqtt_reconnect_timeout then
			log:error("Destroy client and reconnect!")
			client:destroy()
			self._mqtt_reconnect_timeout = 1000
			return self:_start_reconnect()
		end

		r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
	end

	--- Worker thread
	while client and not close_client and self._close_connection == nil do
		sys:sleep(0)
		client:loop(50, 1)
	end

	client:disconnect()
	log:notice("Cloud Connection Closed!")
	client:destroy()
	log:notice("Client Destroyed!")

	if self._close_connection then
		sys:wakeup(self._close_connection)
	end
end

function app:_handle_input(src_app, sn, input, prop, value, timestamp, quality)
	local key = self._safe_call(self.pack_key, self, src_app, sn, input, prop)
	if not key then
		return
	end
	self._cov:handle(key, value, timestamp, quality)
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
	mosq.cleanup()
	return true
end

--- 返回应用对象类
return app
