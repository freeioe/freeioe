local class = require 'middleclass'
local opcua = require 'opcua'

local app = class("IOT_OPCUA_CLIENT_APP")
app.API_VER = 1

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = sys:data_api()
	self._log = sys:logger()
	self._connect_retry = 1000
end

function app:is_connected()
	if self._client then
		return true
	end
end

function app:get_device_node(namespace, obj_name)
	if not self:is_connected() then
		self._log:warning("Client is not connected!")
		return
	end

	local client = self._client
	local nodes = self._nodes

	-- 
	local objects = client:getObjectsNode()
	local idx, err = client:getNamespaceIndex(namespace)
	if not idx then
		self._log:warning("Cannot find namespace", err)
		return
	end
	local devobj, err = objects:getChild(idx..":"..obj_name)
	if not devobj then
		self._log:error('Device object not found', err)
	else
		self._log:debug("Device object found", devobj)
	end

	return {
		idx = idx,
		name = obj_name,
		device = device,
		devobj = devobj,
		vars = {}
	}
end

local inputs = {
	{ name = "Counter1", desc = "Counter1"},
}

function app:on_connected(client)
	-- Cleanup nodes buffer
	self._nodes = {}
	-- Set client object
	self._client = client

	--- Get opcua object instance by namespace and browse name
	local namespace = self._conf.namespace or "http://www.prosysopc.com/OPCUA/SimulationNodes"
	local obj_name = "Simulation"
	local node, err = self:get_device_node(namespace, obj_name)
	if node then
		for _,v in ipairs(inputs) do
			local var, err = node.devobj:getChild(v.name)
			print(_,v.name,var)
			if not var then
				self._log:error('Variable not found', err)
			else
				node.vars[v.name] = var
			end
		end
		local sn = namespace..'/'..obj_name
		self._nodes[sn] = node
	end
end

function app:on_disconnect()
	self._nodes = {}
	self._client = nil
	self._sys:timeout(self._connect_retry, function() self:connect_proc() end)
	self._connect_retry = self._connect_retry * 2
	if self._connect_retry > 2000 * 64 then
		self._connect_retry = 2000
	end
end

function app:connect_proc()
	self._log:notice("OPC Client start connection!")
	local client = self._client_obj

	local ep = self._conf.endpoint or "opc.tcp://172.30.1.162:53530/OPCUA/SimulationServer"
	local username = self._conf.username or "user1"
	local password = self._conf.password or "password"
	--local r, err = client:connect_username(ep, username, password)
	local r, err = client:connect(ep)
	if r then
		self._log:notice("OPC Client connect successfully!", self._sys:time())
		self._connect_retry = 2000
		self:on_connected(client)
	else
		self._log:error("OPC Client connect failure!", err, self._sys:time())
		self:on_disconnect()
	end
end

function app:start()
	self._nodes = {}
	self._devs = {}

	local config = opcua.ConnectionConfig.new()
	config.protocolVersion = 0
	config.sendBufferSize = 65535
	config.recvBufferSize = 65535
	config.maxMessageSize = 0
	config.maxChunkCount = 0

	local client = opcua.Client.new(5000, 10 * 60 * 1000, config)
	self._client_obj = client

	self._sys:fork(function() self:connect_proc() end)
	self._api:set_handler({
		on_output = function(...)
			print(...)
		end,
		on_ctrl = function(...)
			print(...)
		end
	})

	local dev = self._api:add_device('TEST', inputs)
	self._devs['Simulation'] = dev

	return true
end

function app:close(reason)
	print('close', self._name, reason)
	self._client = nil
	if self._client_obj then
		self._nodes = {}
		self._client_obj:disconnect()
		self._client_obj = nil
	end
end

function app:run(tms)
	if not self._client then
		return 1000
	end

	for sn, node in pairs(self._nodes) do
		local dev = self._devs[node.name]
		assert(dev)
		for k, v in pairs(node.vars) do
			local dv = v:getValue()
			--[[
			print(dv, dv:isEmpty(), dv:isScalar())
			print(dv:asLong(), dv:asDouble(), dv:asString())
			]]--
			local now = self._sys:time()
			dev:set_input_prop(k, "value", dv:asLong(), now, 0)
		end
	end

	return 2000
end

return app

