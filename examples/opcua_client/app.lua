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
	self._input_count_in = 0
	self._input_count_out = 0
end

local default_vals = {
	int = 0,
	string = '',
}

local function create_var(idx, devobj, input, device)
	local var, err = devobj:getChild(input.name)
	if var then
		var:setDescription(opcua.LocalizedText.new("zh_CN", input.desc))
		return var
	end
	local attr = opcua.VariableAttributes.new()
	attr.displayName = opcua.LocalizedText.new("zh_CN", input.name)
	if input.desc then
		attr.description = opcua.LocalizedText.new("zh_CN", input.desc)
	end

	local current = device:get_input_prop(input.name, 'value')
	local val = input.vt and default_vals[input.vt] or 0.0
	attr.value = opcua.Variant.new(current or val)

	--[[
	attr.writeMask = opcua.WriteMask.ALL
	attr.userWriteMask = opcua.WriteMask.ALL
	]]
	attr.accessLevel = opcua.AccessLevel.READ ~ opcua.AccessLevel.WRITE ~ opcua.AccessLevel.STATUSWRITE
	--attr.userAccessLevel = opcua.AccessLevel.READ ~ opcua.AccessLevel.READ ~ opcua.AccessLevel.STATUSWRITE
	
	--return devobj:addVariable(opcua.NodeId.new(idx, input.name), input.name, attr)
	return devobj:addVariable(opcua.NodeId.new(idx, 0), input.name, attr)
end

local function set_var_value(var, value, timestamp, quality)
	local val = opcua.DataValue.new(opcua.Variant.new(value))
	val.status = quality
	local tm = opcua.DateTime.fromUnixTime(math.floor(timestamp)) +  math.floor((timestamp%1) * 100) * 100000
	val.sourceTimestamp = tm
	var:setDataValue(val)
end

function app:is_connected()
	if self._client then
		return true
	end
end

function app:create_device_node(sn, props)
	if not self:is_connected() then
		return
	end

	local client = self._client
	local log = self._log
	local idx = self._idx
	local nodes = self._nodes
	local device = self._api:get_device(sn)

	-- 
	local objects = client:getObjectsNode()
	local namespace = self._conf.namespace or "http://iot.symid.com"
	local idx, err = client:getNamespaceIndex(namespace)
	if not idx then
		log:warning("Cannot find namespace", err)
		return
	end
	local devobj, err = objects:getChild(idx..":"..sn)
	if not devobj then
		local attr = opcua.ObjectAttributes.new()
		attr.displayName = opcua.LocalizedText.new("zh_CN", "Device "..sn)
		devobj, err = objects:addObject(opcua.NodeId.new(idx, sn), sn, attr)
		if not devobj then
			log:warning('Create device object failed, error', err)
			return
		else
			log:debug('Device created', devobj)
		end
	else
		log:debug("Device object found", devobj)
	end

	local node = nodes[sn] or {
		idx = idx,
		device = device,
		devobj = devobj,
		vars = {}
	}
	local vars = node.vars
	for i, input in ipairs(props.inputs) do
		local var = vars[input.name]
		if not var then
			local var = create_var(idx, devobj, input, device)
			vars[input.name] = var
		else
			var:setDescription(opcua.LocalizedText.new("zh_CN", input.desc))
		end
	end
	nodes[sn] = node
end

function app:on_add_device(app, sn, props)
	if not self:is_connected() then
		return
	end
	return self:create_device_node(sn, props)
end

function app:on_mod_device(app, sn, props)
	if not self:is_connected() then
		return
	end

	local node = self._nodes[sn]
	local idx = self._idx

	if not node or not node.vars then
		return on_add_device(app, sn, props)
	end

	local vars = node.vars
	for i, input in ipairs(props.inputs) do
		local var = vars[input.name]
		if not var then
			vars[input.name] = create_var(idx, node.devobj, input, node.device)
		else
			var:setDescription(opcua.LocalizedText.new("zh_CN", input.desc))
		end
	end
end

function app:on_del_device(app, sn)
	if not self:is_connected() then
		return
	end
	
	local node = self._nodes[sn]
	if not node then
		return
	end
	
	self._client:deleteNode(node.devobj.id)
	self._nodes[sn] = nil
end

function app:on_post_input(app, sn, input, prop, value, timestamp, quality)
	if not self:is_connected() then
		return
	end

	local node = self._nodes[sn]
	if not node or not node.vars then
		log:error("Unknown sn", sn)
		return
	end
	local var = node.vars[input]
	if var and prop == 'value' then
		self._input_count_in = self._input_count_in + 1
		local r, err = pcall(set_var_value, var, value, timestamp, quality)
		self._input_count_out = self._input_count_out + 1
		if not r then
			self._log:error("OPC Client failure!", err, self._sys:time())
		end
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

	local ep = self._conf.endpoint or "opc.tcp://127.0.0.1:4840"
	local username = self._conf.username or "user1"
	local password = self._conf.password or "password"
	local r, err = client:connect_username(ep, username, password)
	if r then
		self._log:notice("OPC Client connect successfully!", self._sys:time())
		self._client = client
		self._connect_retry = 2000
		
		local devs = self._api:list_devices() or {}
		for sn, props in pairs(devs) do
			self:create_device_node(sn, props)
		end
	else
		self._log:error("OPC Client connect failure!", err, self._sys:time())
		self:on_disconnect()
	end
end

function app:print_debug()
	while true do
		if self._client then
			if 0 == self._client:getState() then
				self._sys:fork(function()
					self:on_disconnect()
				end)
			end
		end
		--print(self._input_count_in, self._input_count_out)
		self._sys:sleep(2000)
	end
end

function app:start()
	self._nodes = {}

	local config = opcua.ConnectionConfig.new()
	config.protocolVersion = 0
	config.sendBufferSize = 65535
	config.recvBufferSize = 65535
	config.maxMessageSize = 0
	config.maxChunkCount = 0

	local client = opcua.Client.new(5000, 10 * 60 * 1000, config)
	self._client_obj = client

	self._sys:fork(function() self:print_debug() end)
	self._sys:fork(function() self:connect_proc() end)
	self._api:set_handler({
		on_add_device = function(app, sn, props)
			return self:on_add_device(app, sn, props)
		end,
		on_del_device = function(app, sn)
			return self:on_del_device(app, sn)
		end,
		on_mod_device = function(app, sn, props)
			return self:on_mod_device(app, sn, props)
		end,
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			return self._sys:post('input', app, sn, input, prop, value, timestamp, quality)
		end,
	}, true)

	return true
end

function app:close(reason)
	print(self._name, reason)
	self._client = nil
	if self._client_obj then
		self._nodes = {}
		self._client_obj:disconnect()
		self._client_obj = nil
	end
end

function app:run(tms)
	return 1000
end

return app

