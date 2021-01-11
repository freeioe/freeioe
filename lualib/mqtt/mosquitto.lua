--- Simulate the MOSQ interface
--
local class = require 'middleclass'
local skynet = require 'skynet'
local mqtt = require 'mqtt'

local mosq = class('mqtt.mosq')

local _M = {
	new = function(...)
		return mosq:new(...)
	end,
	init = function(...)
		mqtt.get_ioloop(true, {
			timeout = 0.05,
			sleep_function = function(timeout)
				skynet.sleep(timeout * 100)
			end
		})
	end,
	version = function()
		return mqtt._VERSION
	end,
	cleanup = function()
	end,
	PROTOCOL_V31 = nil,
	PROTOCOL_V311 = mqtt.v311,
	PROTOCOL_V5 = mqtt.v50,
}

function mosq:initialize(mqtt_id, clean_session)
	self._mqtt_id = mqtt_id
	self._clean_session = clean_session == true
	self._client = nil
	self._packet_id = 0
end

function mosq:reinitialise(mqtt_id, clean_session)
	if self._client then
		self._client:close_connection('reinitialise')
		self._client = nil
	end
	mosq.initialize(self)
	return true
end

function mosq:will_set(topic, payload, qos, retain)
	assert(self._client == nil, "Cannot perform on connected client")
	self._will = {
		topic = topic,
		payload = payload,
		qos = qos,
		retain = retain
	}
	return true
end

function mosq:will_clear()
	if self._client then
		return nil, "Cannot perform on connected client"
	end
	self._will = nil
	return true
end

function mosq:login_set(username, password)
	assert(self._client == nil, "Cannot perform on connected client")
	self._username = username
	self._password = password
	return true
end

function mosq:tls_set(ca_file, ca_path, cert_file, key_file)
	assert(self._client == nil, "Cannot perform on connected client")
	self._ca_file = ca_file
	self._ca_path = ca_path
	self._cert_file = cert_file
	self._key_file = key_file
end

function mosq:tls_insecure_set(value)
	assert(self._client == nil, "Cannot perform on connected client")
	self._tls_insecure = value
end

function mosq:tls_psk_set(psk, identity, ciphers)
	assert(self._client == nil, "Cannot perform on connected client")
	self._tls = {
		psk = psk,
		identity = identity,
		ciphers = ciphers
	}
end

function mosq:tls_opts_set(cert, tls_version, ciphers)
	assert(self._client == nil, "Cannot perform on connected client")
	self._tls_opts = {
		cert = cert,
		tls_version = tls_version,
		ciphers = ciphers
	}
end

function mosq:version_set(version)
	assert(self._client == nil, "Cannot perform on connected client")
	self._version = version
end

function mosq:threaded_set(value)
	return nil, -1, "Not supported"
end

function mosq:option(value)
	return nil, -1, "Not supported"
end

function mosq:connect(host, port, keepalive)
	assert(self._client == nil, "Already connected")
	self._host = host
	self._port = port
	self._keepalive = keepalive

	local client = mqtt.client({
		id = self._mqtt_id,
		clean = self._clean_session,
		uri = self._host..':'..self._port,
		keep_alive = self._keepalive,
		reconnect = true,
		username = self._username,
		password = self._password,
		will = self._will,
		version = self._version
	})

	local function protect_call(func, ...)
		assert(func)
		local r, err = xpcall(func, debug.traceback, ...)
		if not r then
			self.ON_LOG('error', err)
		end
	end

	client:on({
		connect = function(ack)
			protect_call(self.ON_CONNECT, ack.rc == 0, ack.rc, ack:reason_string())
		end,
		message = function(msg)
			client:acknowledge(msg)
			protect_call(self.ON_MESSAGE, msg.packet_id, msg.topic, msg.payload, msg.qos, msg.retain)
		end,
		error = function(err)
			protect_call(self.ON_LOG, 'error', err)
		end,
		close = function(conn)
			protect_call(self.ON_CONNECT, true, 0, conn.close_reason)
		end,
		acknowledge = function(ack)
			protect_call(self.ON_PUBLISH, ack.packet_id)
		end,
		auth = function(...)
			print('auth', ...)
		end
	})
	self._client = client

	return self._client:start_connecting()
end

function mosq.ON_LOG(level, ...)
	skynet.error(level, ...)
end

function mosq.ON_CONNECT(success, rc, msg)
end

function mosq.ON_DISCONNECT(success, rc, msg)
end

function mosq.ON_PUBLISH(packet_id)
end

function mosq.ON_MESSAGE(packet_id, topic, payload, qos, retain)
end

function mosq:connect_async(...)
	--- Using connect
	return mosq:connect(...)
end

function mosq:reconnect()
	assert(self._client, "Not connected")

	self._client:close_connection('reconnect')
	return self:connect(self._host, self._port, self._keepalive)
end

function mosq:disconnect()
	assert(self._client, "Not connected")
	return self._client:close_connection('close connection')
end

function mosq:destory()
	self._client = nil
	return true
end

function mosq:gen_packet_id()
	if self._packet_id >= 0xFFFF then
		self._packet_id = 0
	end
	self._packet_id = self._packet_id + 1
	return self._packet_id
end

function mosq:publish(topic, payload, qos, retain, props, user_props)
	assert(self._client, "Not connected")
	return self._client:publish({
		topic = topic,
		payload = payload,
		qos = qos,
		retain = retain,
		properties = props,
		user_properties = user_props,
		packet_id = self:gen_packet_id()
	})
end

function mosq:subscribe(topic, qos, no_local, retain_as_published, retain_handling, props, user_props)
	return self._client:subscribe({
		topic = topic,
		qos = qos,
		no_local = no_local,
		retain_as_published = retain_as_published,
		retain_handling = retain_handling,
		properties = props,
		user_properties = user_props,
		packet_id = self:gen_packet_id()
	})
end

function mosq:unsubscribe(topic, props, user_props)
	return self._client:unsubscribe({
		topic = topic,
		properties = props,
		user_properties = user_props,
		packet_id = self:gen_packet_id()
	})
end

function mosq:loop(timeout, max_packets)
	return self:loop_forever(timeout, max_packets)
end

function mosq:loop_forever(timeout, max_packets)
	assert(self._client, "Not connected")
	local client = self._client
	local ioloop = mqtt.get_ioloop()
	ioloop:add(client)
	if not timeout  or timeout == -1 then
		--[[
		while client.connection do
			client:_sync_iteration()
		end
		]]--
		ioloop:run_util_clients()
	else
		local start = skynet.now()
		while (skynet.now() - start) < (timeout / 1000) and client.connection do
			ioloop:iteration()	
		end
		ioloop:remove(client)
	end
end

function mosq:loop_start()
	assert(nil, "Not implemented")
end

function mosq:loop_stop()
	assert(nil, "Not implemented")
end

function mosq:socket()
	assert(nil, "Not implemented")
end

return _M
