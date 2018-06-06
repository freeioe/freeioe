local class = require 'middleclass'
local mosq = require 'mosquitto'
local cjson = require 'cjson.safe'
local aliyun_http = require('aliyun_http')

local sub_topics = {
	"app/#",
	"sys/#",
	"output/#",
	"command/#",
}

local mqtt_reconnect_timeout = 100

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("BAIDU_IOT_CLOUD")
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

	self._mqtt_id = conf.mqtt_id or sys:id() -- using system device id
	self._product_key = conf.product_key or "5NjhcjHuFPS"
	self._device_name = conf.device_name or "demo1"
	self._device_secret = conf.device_secret or "QnINbT0Oze4YHCe83lsVvM6RQH66BnLA"
	self._mqtt_host = conf.server or "iot-as-mqtt.cn-shanghai.aliyuncs.com"
	self._mqtt_port = conf.port or "1883"
	self._enable_tls = conf.enable_tls or false
	self._enable_https = conf.enable_https or false
	self._http_server = conf.http_server or "iot-auth.cn-shanghai.aliyuncs.com"
	self._http_api = aliyun_http:new(sys, self._http_server, self._product_key)

	self._close_connection = false
end

-- @param app: 应用实例对象
local function create_handler(app)
	local api = app._api
	local server = app._server
	local log = app._log
	local self = app
	return {
		--- 处理设备对象添加消息
		on_add_device = function(app, sn, props)
			return self:fire_devices(1000)
		end,
		--- 处理设备对象删除消息
		on_del_device = function(app, sn)
			return self:fire_devices(1000)
		end,
		--- 处理设备对象修改消息
		on_mod_device = function(app, sn, props)
			return self:fire_devices()
		end,
		--- 处理设备输入项数值变更消息
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			return self:handle_input(app, sn, input, prop, value, timestamp, quality)
		end,
		on_event = function(app, sn, level, data, timestamp)
			return self:handle_event(app, sn, level, data, timestamp)
		end,
		on_stat = function(app, sn, stat, prop, value, timestamp)
			return self:handle_stat(app, sn, stat, prop, value, timestamp)
		end,
	}
end

function app:start_reconnect()
	self._mqtt_client = nil
	self._sys:timeout(mqtt_reconnect_timeout, function() self:connect_proc() end)
	mqtt_reconnect_timeout = mqtt_reconnect_timeout * 2
	if mqtt_reconnect_timeout > 10 * 60 * 100 then
		mqtt_reconnect_timeout = 100
	end

end

function app:handle_input(app, sn, input, prop, value, timestamp, quality)
	local msg = {
		app = app,
		sn = sn,
		input = input,
		prop = prop,
		value = value,
		timestamp = timestamp,
		quality = quality
	}
	if self._mqtt_client then
		self._mqtt_client:publish("/data", cjson.encode(msg), 1, false)
	end
end

function app:handle_event(app, sn, level, data, timestamp)
	local msg = {
		app = app,
		sn = sn,
		level = level,
		data = data,
		timestamp = timestamp,
	}
	if self._mqtt_client then
		self._mqtt_client:publish("/event", cjson.encode(msg), 1, false)
	end
end

function app:handle_stat(app, sn, stat, prop, value, timestamp)
	local msg = {
		app = app,
		sn = sn,
		stat = stat,
		prop = prop,
		value = value,
		timestamp = timestamp,
	}
	if self._mqtt_client then
		self._mqtt_client:publish("/statistics", cjson.encode(msg), 1, false)
	end
end

function app:fire_devices(timeout)
	local timeout = timeout or 100
	if self._fire_device_timer  then
		return
	end

	self._fire_device_timer = function()
		local devs = self._api:list_devices() or {}
		if self._mqtt_client then
			self._mqtt_client:publish("/devices", cjson.encode(devs), 1, true)
		end
	end

	self._sys:timeout(timeout, function()
		if self._fire_device_timer then
			self._fire_device_timer()
			self._fire_device_timer = nil
		end
	end)
end

function app:create_mqtt_client()
	local mqtt_id = self._mqtt_id
	local clean_session = self._clean_session or true
	local host = self._product_key.."."..self._mqtt_host
	local port = self._mqtt_port

	if not self._enable_https then
		local timestamp = os.time() * 1000
		local securemode = self._enable_tls and 2 or 3
		local client_id = mqtt_id.."|securemode="..securemode..",signmethod=hmacsha1,timestamp="..timestamp.."|"
		local username = self._device_name.."&"..self._product_key
		local password = self._http_api:gen_sign(self._device_name, self._device_secret, mqtt_id, timestamp)

		self._log:debug("Aliyun MQTT Client", client_id, username, password)
		local client = assert(mosq.new(client_id, clean_session))
		client:version_set(mosq.PROTOCOL_V311)
		client:login_set(username, password)
		if self._enable_tls then
			client:tls_set(self._sys:app_dir().."/root_cert.crt")
		end
		return client, host, port
	else
		local r, err = self._http_api:auth(self._device_name, self._device_secret, mqtt_id)
		if not r then
			self._log:error("Auth failed", err)
			return nil
		end

		self._refresh_token_timeout = os.time() + (24 * 3600)

		local username = r.iotId
		local password = r.iotToken
		self._log:debug("Aliyun MQTT Client", mqtt_id, username, password)

		local client = assert(mosq.new(mqtt_id, clean_session))
		client:version_set(mosq.PROTOCOL_V311)
		client:login_set(username, password)
		client:tls_set(self._sys:app_dir().."/root_cert.crt")

		if r.resources and r.resources.mqtt then
			host = r.resources.mqtt.host
			port = r.resources.mqtt.port
		end
		
		return client, host, port
	end
end

function app:connect_proc()
	local log = self._log
	local sys = self._sys

	local mqtt_id = self._mqtt_id
	-- 创建MQTT客户端实例
	local client, mqtt_host, mqtt_port = self:create_mqtt_client(mqtt_id)
	self._log:debug("Aliyun MQTT Server", mqtt_host, mqtt_port)

	-- 注册回调函数
	client.ON_CONNECT = function(success, rc, msg) 
		if success then
			log:notice("ON_CONNECT", success, rc, msg) 
			client:publish("/status", cjson.encode({device=mqtt_id, status="ONLINE"}), 1, true)
			self._mqtt_client = client
			self._mqtt_client_last = sys:time()
			for _, v in ipairs(sub_topics) do
				client:subscribe("/"..v, 1)
			end
			--client:subscribe("+/#", 1)
			--
			mqtt_reconnect_timeout = 100
			self:fire_devices(1000)
		else
			log:warning("ON_CONNECT", success, rc, msg) 
			self:start_reconnect()
		end
	end
	client.ON_DISCONNECT = function(success, rc, msg) 
		log:warning("ON_DISCONNECT", success, rc, msg) 
		if self._mqtt_client then
			self:start_reconnect()
		end
	end
	client.ON_LOG = function(...)
		--print(...)
	end
	client.ON_MESSAGE = function(...)
		print(...)
	end

	client:will_set("/status", cjson.encode({device=mqtt_id, status="OFFLINE"}), 1, true)

	self._close_connection = false
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
				sys:timeout(100, function() self:connect_proc() end)
				-- We meet bug that if client reconnect to broker with lots of failures, it's socket will be broken. 
				-- So we will re-create the client
				return
			end
		end
	end

	self._mqtt_client = client

	--- Worker thread
	while self._mqtt_client and not self._close_connection do
		sys:sleep(0)
		if self._mqtt_client then
			self._mqtt_client:loop(50, 1)
		else
			sys:sleep(50)
		end
	end
	if self._mqtt_client then
		self._mqtt_client:disconnect()
		self._mqtt_client = nil
		log:notice("Cloud Connection Closed!")
	end
end

function app:disconnect()
	if not self._mqtt_client then
		return
	end

	self._log:debug("Cloud Connection Closing!")
	self._close_connection = true
	while self._mqtt_client do
		self._sys:sleep(10)
	end
	return true
end

--- 应用启动函数
function app:start()
	--- 设定回调处理对象
	self._handler = create_handler(self)
	self._api:set_handler(self._handler, true)

	self._sys:fork(function()
		self:connect_proc()
	end)

	self._log:debug("Aliyun MQTT connector started!")
	
	return true
end

--- 应用退出函数
function app:close(reason)
	mosq.cleanup()
end

--- 应用运行入口
function app:run(tms)
	if self._refresh_token_timeout and self._refresh_token_timeout - os.time() < 60  then
		--self:huawei_http_refresh_token()
	end

	return 1000 * 10 -- 10 seconds
end

--- 返回应用对象
return app

