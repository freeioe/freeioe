local skynet = require 'skynet'
local class = require 'middleclass'
local mqtt = require 'mqtt'
local index_stack = require 'utils.index_stack'

----
-- Configuration:
-- client_id - MQTT client id (默认使用网关id)
-- username - 认证时使用的用户名
-- password - 认证时使用的密码
-- server - MQTT 服务器地址
-- port - MQTT服务器端口
-- keep_alive --
-- reconnect -- number in seconds
-- tls - MQTT with TLS
-- tls:protocol - tlsv1_2
-- tls:insecure --
-- tls:ca_file - MQTT Server cert file
-- tls:ca_path -- Server cert file folder
-- tls:cert --
-- tls:key --
-- tls:key_password
-- qos - QOS buffer
-- qos:max
--

local client = class("FREEIOE_MQTT_HELPER")

client.static.V30 = mqtt.v30
client.static.V311 = mqtt.v311
client.static.V50 = mqtt.v50

---
function client:initialize(opt, logger)
	self._log = logger
	opt.host = opt.host or '127.0.0.1'
	self._opt = {
		id = opt.client_id,
		clean = opt.clean_session,
		username = opt.username,
		password = opt.password,
		uri = opt.port and opt.host..':'..opt.port or opt.host,
		keep_alive = opt.keep_alive,
		reconnect = opt.reconnect ~= nil and opt.reconnect or 5,
		version = opt.version,
		will = opt.will,
	}
	if opt.tls then
		local tls = opt.tls
		self._opt.secure = {
			mode = 'client',
			protocol = tls.protocol or 'tlsv1_2',
			verify = tls.insecure and 'none' or 'peer',
			options = 'all',
			cafile = tls.ca_file,
			capath = tls.ca_path,
			certificate = tls.cert,
			key = tls.key,
			passwd = tls.key_passwd,
			params = {
				host = opt.host
			}
		}
	end

	self._safe_call = function(f, ...)
		local r, er, err = xpcall(f, debug.traceback, ...)
		if not r then
			self._log:warning('Code bug', er, err)
			return nil, er and tostring(er) or nil
		end
		return er, er and tostring(err) or nil
	end

	self._connecting = nil
	self._close_connection = nil
	self._max_mqtt_reconnect_timeout = 128 * 100 -- about two mins
	
	if not mqtt.get_ioloop(false) then
		mqtt.get_ioloop(true, {
			timeout = 1,
			--[[
			sleep = 0.01,
			]]--
			sleep_function = function(timeout)
				skynet.sleep(math.floor(timeout * 100))
			end
		})
	end

	if opt.qos then
		local qos = type(opt.qos) == 'table' and opt.qos or {}
		qos.max = qos.max or 1024
		qos.sleep = qos.sleep_ten or 10
		qos.reset_id = qos.reset_id ~= nil and qos.reset_id or true
		qos.on_drop = qos.on_drop or function(...)
			self._log:error("MQTT QOS message dropped!!")
		end

		self._qos_msg_buf = index_stack:new(qos.max, qos.on_drop)
		self._qos = qos
	end
end

function client:connected()
	return self._client ~= nil and self._client.connection
end

function client:socket()
	if not self._client then
		return -1
	end
	if not self._client.connection then
		return -1
	end

	return assert(self._client.connection.socket_id)
end

function client:publish(topic, payload, qos, retain, props, user_props)
	local qos = qos == nil and 0 or qos
	local retain = retain == nil and false or retain

	if not self:connected() then
		self._log:trace("MQTT not connected!")
		return nil, "MQTT not connected!"
	end

	local packet_id, err = self._client:publish({
		topic = topic, 
		payload = payload,
		qos = qos,
		retain = retain,
		properties = props,
		user_properities = user_props
	})

	if qos == 1 and packet_id and self._qos_msg_buf then
		self._qos_msg_buf:push(packet_id, topic, payload, qos, retain, props, user_props)
	end
	return packet_id, err
end

function client:mqtt_resend_qos_msg()
	if not self._qos_msg_buf or self._qos_msg_buf:size() == 0 then
		return
	end

	skynet.fork(function()
		self._qos_msg_buf:fire_all(function(...)
			return self:publish(...)
		end, self._qos.sleep_ten, self._qos.reset_id)
	end)
end

function client:subscribe(topic, qos, no_local, retain_as_published, retain_handling, props, user_props)
	if not self:connected() then
		return nil, "MQTT not connected!"
	end
	return self._client:subscribe({
		topic = topic, 
		qos = qos or 1,
		no_local = no_local,
		retain_as_published = retain_as_published,
		retain_handling = retain_handling,
		properties = props,
		user_properties = user_props
	})
end

function client:unsubscribe(topic, props, user_props)
	if not self:connected() then
		return nil, "MQTT not connected!"
	end
	return self._client:unsubscribe({
		topic = topic,
		properties = props,
		user_properties = user_props
	})
end

function client:connect()
	if self._client then
		return nil, "Already connected"
	end

	local client = mqtt.client(self._opt)

	client:on({
		connect = function(ack)
			self._safe_call(self.ON_CONNECT, self, ack.rc == 0, ack.rc, ack:reason_string())
		end,
		message = function(msg)
			client:acknowledge(msg)
			self._safe_call(self.on_mqtt_message, self, msg.packet_id, msg.topic, msg.payload, msg.qos, msg.retain)
		end,
		error = function(err)
			self._safe_call(self.ON_ERROR, self, err)
		end,
		close = function(conn)
			self._safe_call(self.ON_DISCONNECT, self, conn)
		end,
		acknowledge = function(ack)
			self._safe_call(self.ON_PUBLISH, self, ack)
		end,
		auth = function(...)
			print('auth', ...)
		end
	})
	self._client = client

	skynet.fork(function()
		self:_connect_proc()
	end)

	return true
end

function client:disconnect()
	if self._close_connection then
		return nil, "Connection is closing"
	end

	self._log:debug("MQTT connection closing!")

	self._close_connection = {}

	if self._connecting then
		skynet.wakeup(self._connecting)
	else
		if self._client then
			self._log:debug("Disconnect MQTT client!")
			self._client:disconnect()
		end
	end

	skynet.wait(self._close_connection)
	assert(self._client == nil)
	self._close_connection = nil

	if self._qos_msg_buf then
		self._qos_msg_buf:clean()
	end

	self._log:debug("MQTT connection closed!")

	return true
end

function client:_connect_proc()
	local log = self._log
	local client = self._client

	-- 创建MQTT客户端实例
	log:debug("MQTT Connect:", self._opt.id, self._opt.uri, self._opt.username, self._opt.password)

	--[[
	local ts = 100
	while not self._close_connection do
		local r, err = client:start_connecting()
		if r then
			break
		end
		if self._close_connection then
			break
		end
		--log:error(string.format("Connect to broker %s:%d failed! error:%s", mqtt_host, mqtt_port, err))
		ts = ts * 2
		if ts > self._max_mqtt_reconnect_timeout then
			ts = 100
		end
		self._connecting = {}
		print('sleep', ts)
		skynet.sleep(ts, self._connecting)
		self._connecting = nil
	end
	]]--

	--- Worker thread
	if not self._close_connection then
		mqtt.run_ioloop(self._client)
	end

	log:notice("MQTT run_ioloop quited!")

	if self._close_connection then
		log:notice("Close mqtt connection!")
		client:disconnect()
		self._client = nil
		skynet.wakeup(self._close_connection)
	else
		-- Try disconnect to make sure it disconnected
		client:disconnect()
		skynet.fork(function()
			self:_connect_proc()
		end)
	end
end

function client:on_mqtt_message(packet_id, topic, payload, qos, retain)
end

function client:on_mqtt_connect(success, msg)
end

function client:on_mqtt_disconnect(msg)
end

function client:ON_CONNECT(success, rc, msg) 
	if success then
		self._log:notice("ON_CONNECT SUCCESS", self:socket(), rc, msg) 
	end

	if success then
		self:mqtt_resend_qos_msg()
	end

	self._safe_call(self.on_mqtt_connect, self, success, msg)
end

function client:ON_DISCONNECT(conn)
	local msg = conn and conn.close_reason or 'Unknown disconnect reason'
	self._log:warning("ON_DISCONNECT", msg) 

	self._safe_call(self.on_mqtt_disconnect, self, msg)
end

function client:ON_PUBLISH(ack)
	local mid = ack.packet_id
	if self._qos_msg_buf then
		self._qos_msg_buf:remove(mid)
	end
	if self.on_mqtt_publish then
		self._safe_call(self.on_mqtt_publish, self, mid)
	end
end

function client:ON_ERROR(err)
	self._log:error(err)
end

return client
