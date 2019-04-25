local class = require 'middleclass'
local mosq = require 'mosquitto'
local cjson = require 'cjson.safe'
local periodbuffer = require 'buffer.period'
local ioe = require 'ioe'
local cov = require 'cov'

return function(app_class, api_ver)
	local zlib_loaded, zlib -- will be initialized in init(...)
	local safe_call

	--- 注册对象(请尽量使用唯一的标识字符串)
	local app = class(app_class or "__XXX_CLOUD_MQTT")
	--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
	app.API_VER = api_ver or 1

	----
	-- Your handlers are:
	-- app_start
	-- app_close
	-- app_run
	-- on_add_device
	-- on_mod_device
	-- on_del_device
	-- pack_devices -- 当上述设备回调不存在，会调用此接口进行设备描述打包，不存在则忽略设备上送
	-- pack_key -- 用于打包: src_app:采集应用名称 sn:采集设备序列号 input: 输入项迷宫昵称
	-- publish_data -- 用于未开启PB时的但数据点回调 (key, value, timestamp, quality)
	-- publish_data_list -- 用于开启PB后，打包上送 (list --成员为 [key, value, timestamp, quality])
	-- on_connect_ok -- 用于MQTT连接成功回调
	--
	-- The function from this helper
	-- connected -- 连接状态
	-- connect -- 开启连接(应用启动会自动开启一次连接)
	-- disconnect -- 断开连接
	-- mqtt_publish -- 发布MQTT消息
	-- compress -- 压缩数据
	-- decompress -- 解压数据

	---
	-- 应用对象初始化函数
	-- @param name: 应用本地安装名称。 如modbus_com_1
	-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
	-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
	function app:initialize(name, sys, conf)
		self._name = name
		self._sys = sys
		self._conf = conf
		--- 获取数据接口
		self._api = sys:data_api()
		--- 获取日志接口
		self._log = sys:logger()

		safe_call = function(f, ...)
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
		self._mqtt_host = conf.server or "127.0.0.1"
		self._mqtt_port = conf.port or "1883"

		-- COV and PB
		self._period = tonumber(conf.period) or 60
		self._ttl = tonumber(conf.ttl) or 300
		self._float_threshold = tonumber(conf.float_threshold) or 0.000001

		self._close_connection = nil
		self._mqtt_reconnect_timeout = 1000

		zlib_loaded, zlib = pcall(require, 'zlib')

		self._total_compressed = 0
		self._total_uncompressed = 0

		if self.app_initialize then
			self:app_initialize(name, sys, conf)
		end
	end

	function app:connected()
		return self._mqtt_client
	end

	function app:mqtt_publish(topic, data, qos, retained)
		local qos = qos or 1
		local retained = retained or false
		if not self._mqtt_client then
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
		local deflate = zlib.deflate()
		local deflated, eof, bytes_in, bytes_out = deflate(data, 'finish')
		self:_calc_compress(bytes_in, bytes_out) 
		return deflated, eof, bytes_in, bytes_out
	end

	function app:decompress(data)
		local inflate = zlib.inflate()
		local inflated, eof, bytes_in, bytes_out = inflate(data, "finish")
		return inflated, eof, bytes_in, bytes_out
	end

	function app:connect()
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

	-- @param app: 应用实例对象
	local function create_handler(app)
		local api = app._api
		local server = app._server
		local log = app._log
		
		assert(app.pack_key, "pack_key callback missing")

		local self = app
		return {
			--- 处理设备对象添加消息
			on_add_device = function(src_app, sn, props)
				if self.on_add_device then
					return safe_call(self.on_add_device, self, src_app, sn, props)
				end
				return self:_fire_devices(1000)
			end,
			--- 处理设备对象删除消息
			on_del_device = function(src_app, sn)
				if self.on_del_device then
					return safe_call(self.on_del_device, self, src_app, sn)
				end
				return self:_fire_devices(1000)
			end,
			--- 处理设备对象修改消息
			on_mod_device = function(src_app, sn, props)
				if self.on_mod_device then
					return safe_call(self.on_mod_device, self, src_app, sn, props)
				end
				return self:_fire_devices()
			end,
			--- 处理设备输入项数值变更消息
			on_input = function(src_app, sn, input, prop, value, timestamp, quality)
				if tonumber(value) == nil then
					return
				end
				return self:_handle_input(src_app, sn, input, prop, value, timestamp, quality)
			end,
			on_event = function(src_app, sn, level, data, timestamp)
				if self.handle_event then
					return self:handle_event(src_app, sn, level, data, timestamp)
				end
			end,
			on_stat = function(src_app, sn, stat, prop, value, timestamp)
				if self.handle_stat then
					return self:handle_stat(src_app, sn, stat, prop, value, timestamp)
				end
			end,
		}
	end

	function app:_start_reconnect()
		self._mqtt_client = nil
		self._sys:timeout(self._mqtt_reconnect_timeout, function() self:_connect_proc() end)
		self._mqtt_reconnect_timeout = self._mqtt_reconnect_timeout * 2
		if self._mqtt_reconnect_timeout > 10 * 60 * 1000 then
			self._mqtt_reconnect_timeout = 1000
		end
	end

	function app:_connect_proc()
		local log = self._log
		local sys = self._sys

		local mqtt_id = self._mqtt_id
		local mqtt_host = self._mqtt_host
		local mqtt_port = self._mqtt_port
		local clean_session = self._clean_session or true
		local username = self._mqtt_username
		local password = self._mqtt_password

		-- 创建MQTT客户端实例
		log:info("MQTT Connect:", mqtt_id, mqtt_host, mqtt_port, username, password)
		local client = assert(mosq.new(mqtt_id, clean_session))
		client:version_set(mosq.PROTOCOL_V311)
		client:login_set(username, password)
		if self._enable_tls then
			client:tls_set(sys:app_dir().."/root_cert.pem")
		end

		-- 注册回调函数
		client.ON_CONNECT = function(success, rc, msg) 
			if success then
				log:notice("ON_CONNECT", success, rc, msg) 
				if self.on_connect_ok then
					-- client:subscribe("/"..v, 1)
					--client:publish("/status", cjson.encode({device=mqtt_id, status="ONLINE"}), 1, true)
					safe_call(self.on_connect_ok, self)
				end

				self._mqtt_client = client
				self._mqtt_client_last = sys:time()
				self._mqtt_reconnect_timeout = 100

				self:_fire_devices(1000)
			else
				log:warning("ON_CONNECT", success, rc, msg) 
				self:_start_reconnect()
			end
		end
		client.ON_DISCONNECT = function(success, rc, msg) 
			log:warning("ON_DISCONNECT", success, rc, msg) 
			if self._mqtt_client then
				self:_start_reconnect()
			end
		end
		client.ON_LOG = function(...)
			--print(...)
		end
		client.ON_MESSAGE = function(packet_id, topic, data, qos, retained)
			--print(packet_id, topic, data, qos, retained)
			if self.on_message then
				safe_call(self.on_message, self, packet_id, topic, data, qos, retained)
			end
		end

		if self.on_will then
			local topic, msg, qos, retained = self:on_will()
			if topic and msg then
				--client:will_set("/status", cjson.encode({device=mqtt_id, status="OFFLINE"}), 1, true)
				client:will_set(topic, msg, qos or 1, retained == nil and true or false)
			end
		end

		local r, err
		local ts = 1
		while not r do
			r, err = client:connect(mqtt_host, mqtt_port, mqtt_keepalive)
			if not r then
				log:error(string.format("Connect to broker %s:%d failed!", mqtt_host, mqtt_port), err)
				sys:sleep(ts * 500)
				ts = ts * 2
				if ts >= 64 then
					client:destroy()
					sys:timeout(100, function() self:_connect_proc() end)
					-- We meet bug that if client reconnect to broker with lots of failures, it's socket will be broken. 
					-- So we will re-create the client
					return
				end
			end
		end

		--- Worker thread
		while client and self._close_connection == nil do
			sys:sleep(0)
			if client then
				client:loop(50, 1)
			else
				sys:sleep(50)
			end
		end

		if client then
			client:disconnect()
			log:notice("Cloud Connection Closed!")
			client:destroy()
		end

		if self._close_connection then
			sys:wakeup(self._close_connection)
		end
	end


	function app:_handle_input(src_app, sn, input, prop, value, timestamp, quality)
		local key = safe_call(self.pack_key, self, src_app, sn, input)
		if not key then
			return
		end
		self._cov:handle(key, value, timestamp, quality)
	end

	function app:_fire_devices(timeout)
		local timeout = timeout or 1000
		if not self.pack_devices then
			return
		end

		if self._fire_device_timer  then
			return
		end

		self._fire_device_timer = function()
			local devs = self._api:list_devices() or {}
			if self._mqtt_client then
				local topic, val = safe_call(self.pack_devices, self, devs)
				if topic and val then
					self._mqtt_client:publish(topic, val, 1, true)
				end
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
			return safe_call(self.publish_data, self, ...)
		else
			return pb:push(...)
		end
	end

	function app:_init_cov()
		local cov_opt = {ttl=300, float_threshold = 0.000001}
		self._cov = cov:new(function(...)
			self:_handle_cov_data(...)
		end, cov_opt)
		self._cov:start()
	end

	function app:_init_pb()
		if not zlib_loaded then
			return
		end

		if self._period < 1 then
			return
		end

		local period = self._period * 1000 -- seconds

		self._pb = periodbuffer:new(period, 1024 * 1024 * 4) -- 4M data points
		self._pb:start(function(...)
			if not self._mqtt_client then
				return nil, "MQTT not connected"
			end
			return safe_call(self.publish_data_list, self, ...)
		end)
	end

	--- 应用启动函数
	function app:start()
		--- 设定回调处理对象
		self._handler = create_handler(self)
		self._api:set_handler(self._handler, true)

		self:_init_cov()
		self:_init_pb()

		if self.app_start then
			local r, err = safe_call(self.app_start, self)
			if not r then
				return nil, err
			end
		end

		self:connect()

		self._log:debug("MQTT Connector Started!")
		
		return true
	end

	--- 应用退出函数
	function app:close(reason)
		self:disconnect()
		mosq.cleanup()
		if self.app_close then
			return safe_call(self.app_close, self, reason)
		end
	end

	--- 应用运行入口
	function app:run(tms)
		if self.app_run then
			return self:app_run(tms)
		end
		return 1000 * 60 -- 60 seconds
	end

	--- 返回应用对象
	return app
end
