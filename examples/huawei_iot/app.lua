local class = require 'middleclass'
local mosq = require 'mosquitto'
local huawei_http = require 'huawei_http'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("HUAWEI_IOT_CLOUD")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

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
	self._nodes = {}
end

-- @param app: 应用实例对象
local function create_handler(app)
	local api = app._api
	local server = app._server
	local log = app._log
	local idx = app._idx
	local nodes = app._nodes
	return {
		--- 处理设备对象添加消息
		on_add_device = function(app, sn, props)
		end,
		--- 处理设备对象删除消息
		on_del_device = function(app, sn)
		end,
		--- 处理设备对象修改消息
		on_mod_device = function(app, sn, props)
		end,
		--- 处理设备输入项数值变更消息
		on_input = function(app, sn, input, prop, value, timestamp, quality)
		end,
	}
end

function app:start_reconnect()
	if true then
		return
	end
	self._mqtt_client = nil
	self._sys:timeout(mqtt_reconnect_timeout, function() self:connect_proc() end)
	mqtt_reconnect_timeout = mqtt_reconnect_timeout * 2
	if mqtt_reconnect_timeout > 10 * 60 * 100 then
		mqtt_reconnect_timeout = 100
	end

end

function app:connect_proc()
	local log = self._log
	local mqtt_id = self._mqtt_id
	local mqtt_host = self._mqtt_host
	local mqtt_port = self._mqtt_port
	local clean_session = self._clean_session or true
	local username = self._username
	local password = self._password

	local client = assert(mosq.new(mqtt_id, clean_session))
	client:version_set(mosq.PROTOCOL_V311)
	client:login_set(username, password)
	client:tls_set(self._sys:app_dir().."/rootcert.pem")
	client:tls_opts_set(0)
	client:tls_insecure_set(1)

	client.ON_CONNECT = function(success, rc, msg) 
		print(success)
		if success then
			log:notice("ON_CONNECT", success, rc, msg) 
			client:publish(mqtt_id.."/status", "ONLINE", 1, true)
			self._mqtt_client = client
			self._mqtt_client_last = self._sys:time()
			--[[
			for _, v in ipairs(wildtopics) do
				--client:subscribe("ALL/"..v, 1)
				client:subscribe(mqtt_id.."/"..v, 1)
			end
			]]--
			mqtt_reconnect_timeout = 100
		else
			log:warning("ON_CONNECT", success, rc, msg) 
			self:start_reconnect()
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg) 
		log:warning("ON_DISCONNECT", success, rc, msg) 
		if not enable_async and self._mqtt_client then
			self:start_reconnect()
		end
	end

	client.ON_LOG = function(...)
		--print(...)
	end
	client.ON_MESSAGE = function(...)
		print(...)
	end

	client:will_set(self._mqtt_id.."/status", "OFFLINE", 1, true)

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
				log:error(string.format("Connect to broker %s:%d failed!", mqtt_host, mqtt_port), err)
				self.sys:sleep(ts * 500)
				ts = ts * 2
				if ts >= 64 then
					client:destroy()
					self.sys:timeout(100, function() self:connect_proc() end)
					-- We meet bug that if client reconnect to broker with lots of failures, it's socket will be broken. 
					-- So we will re-create the client
					return
				end
			end
		end

		self._mqtt_client = client

		--- Worker thread
		while self._mqtt_client and not close_connection do
			self._sys:sleep(0)
			if self._mqtt_client then
				self._mqtt_client:loop(50, 1)
			else
				self._sys:sleep(50)
			end
		end
		if self._mqtt_client then
			self._mqtt_client:disconnect()
			log:notice("Cloud Connection Closed!")
		end
	end
end

function app:disconnect()
	local client = self._mqtt_client
	self._log:debug("Cloud Connection Closing!")

	if enable_async then
		self._mqtt_client = nil
		client:disconnect()
		client:loop_stop()
		self._log:notice("Cloud Connection Closed!")
	else
		close_connection = true
	end
	return true
end

function app:huawei_http_login()
	local api = huawei_http:new(self._sys, "117.78.47.187", "8943", "fxfB_JFz_rvuihHjxOj_kpWcgjQa")

	local device_id = "6bcfe38c-936b-4ffb-9913-54ef2232ba99"
	local secret = "2efe9e3c6d7ca4317c17"
	local r, err = api:login(device_id, secret)
	if r then
		if r and r.refreshToken then
			local srv = r.addrHAServer
			local token = r.refreshToken
			local mqtt_id = r.mqttClientId
			print(srv, token, mqtt_id)
			self._mqtt_id = mqtt_id
			self._mqtt_host = srv
			self._mqtt_port = 8883
			self._username = device_id
			self._password = secret

			self._sys:timeout(10, function() self:connect_proc(true, device_id, secret) end)
		end
	end
end

--- 应用启动函数
function app:start()
	--- 设定回调处理对象
	self._handler = create_handler(self)
	self._api:set_handler(self._handler, true)

	self._sys:fork(function()
		self:huawei_http_login()
	end)

	--[[
	--- List all devices and then create opcua object
	self._sys:fork(function()
		local devs = self._api:list_devices() or {}
		for sn, props in pairs(devs) do
			--- Calling handler for creating opcua object
			self._handler.on_add_device(self, sn, props)
		end
	end)
	]]--
	
	self._log:notice("Started!!!!")
	return true
end

--- 应用退出函数
function app:close(reason)
	mosq.cleanup()
end

--- 应用运行入口
function app:run(tms)
	--- OPCUA模块运行入口
	while self._server.running do
		local ms = self._server:run_once(false)
		--- 暂停OPCUA模块运行，处理IOT系统消息
		self._sys:sleep(ms % 10)
	end
	print('XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX')

	return 1000
end

--- 返回应用对象
return app

