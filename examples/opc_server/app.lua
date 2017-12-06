local class = require 'middleclass'
local opcua = require 'opcua'

local app = class("IOT_OPCUA_SERVER_APP")
app.API_VER = 1

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = sys:data_api()
	self._log = sys:logger()
end

local default_vals = {
	int = 0,
	string = '',
}

local function create_var(idx, devobj, prop)
	local r, var = pcall(devobj.GetChild, devobj, prop.name)
	if r and var then
		var.Description = opcua.LocalizedText.new(prop.desc)
		return var
	end
	local val = prop.vt and default_vals[prop.vt] or 0.0
	local var = devobj:AddVariable(idx, prop.name, opcua.Variant.new(val))
	var.Description = opcua.LocalizedText.new(prop.desc)
	return var
end

local function set_var_value(var, value, timestamp, quality)
	local val = opcua.DataValue.new(value)
	val.Status = quality
	local tm = opcua.DateTime.FromTimeT(math.floor(timestamp), math.floor((timestamp%1) * 1000000))
	val:SetSourceTimestamp(tm)
	val:SetServerTimestamp(opcua.DateTime.Current())
	var.DataValue = val
end

local function create_handler(app)
	local server = app._server
	local nodes = {}
	return {
		on_add_device = function(app, sn, props)
			-- 
			local objects = server:GetObjectsNode()
			local r, idx = pcall(server.GetNamespaceIndex, server, app)
			if not r then
				idx = server:RegisterNamespace(app)
			end
			local id = opcua.NodeId.new(sn, idx)
			local name = opcua.QualifiedName.new("Device "..sn, idx)
			local r, devobj = pcall(objects.GetChild, objects, idx..":Device "..sn)
			if not r or not devobj then
				r, devobj = pcall(objects.AddObject, objects, idx, "Device "..sn)
				if not r then
					app._log:warning('Create device object failed, error', devobj)
					return
				end
			end

			local vars = {}
			for i, prop in ipairs(props.inputs) do
				vars[prop.name] = create_var(idx, devobj, prop)
			end

			nodes[sn] = {
				idx = idx,
				devobj = devobj,
				vars = vars
			}
		end,
		on_del_device = function(app, sn)
			print(app, sn)
		end,
		on_mod_device = function(app, sn, props)
			local node = nodes[sn]
			if not node or not node.vars then
			end
			local vars = node.vars
			for i, prop in ipairs(props.inputs) do
				local var = vars[prop.name]
				if not var then
					vars[prop.name] = create_var(node.idx, node.devobj, prop)
				end
			end
		end,
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			local node = nodes[sn]
			if not node or not node.vars then
				return
			end
			local var = node.vars[input]
			if var and prop == 'value' then
				set_var_value(var, value, timestamp, quality)
			end
		end,
	}
end

function app:start()
	local server = opcua.Server.new(false)
	server:SetEndpoint("opc.tcp://*:4840/freeopcua/server/")
	server:SetServerURI("urn:://iot.freeopcua.symid.com")
	server:Start()

	self._server = server
	self._api:set_handler(create_handler(self), true)
	return true
end

function app:close(reason)
	print(self._name, reason)
	self._server:Stop()
	self._server = nil
end

function app:run(tms)
	return 1000
end

return app

