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

function app:on_add_device(app, sn, props)
	local client = self._client
	local log = self._log
	local idx = self._idx
	local nodes = self._nodes

	-- 
	local objects = client:GetObjectsNode()
	local r, idx = pcall(client.GetNamespaceIndex, client, "http://iot.symid.com")
	if not r then
		log:warning("Cannot find namespace")
		return
	end
	local id = opcua.NodeId.new(sn, idx)
	local name = opcua.QualifiedName.new(sn, idx)
	local r, devobj = pcall(objects.GetChild, objects, idx..":"..sn)
	if not r or not devobj then
		r, devobj = pcall(objects.AddObject, objects, idx, sn)
		if not r then
			log:warning('Create device object failed, error', devobj)
			return
		end
	end

	local node = nodes[sn] or {
		idx = idx,
		devobj = devobj,
		vars = {}
	}
	local vars = node.vars
	for i, prop in ipairs(props.inputs) do
		local var = vars[prop.name]
		if not var then
			vars[prop.name] = create_var(idx, devobj, prop)
		else
			var.Description = opcua.LocalizedText.new(prop.desc)
		end
	end
	nodes[sn] = node

end

function app:on_mod_device(app, sn, props)
	local node = self._nodes[sn]
	local idx = self._idx

	if not node or not node.vars then
	end
	local vars = node.vars
	for i, prop in ipairs(props.inputs) do
		local var = vars[prop.name]
		if not var then
			vars[prop.name] = create_var(idx, node.devobj, prop)
		else
			var.Description = opcua.LocalizedText.new(prop.desc)
		end
	end
end

function app:on_input(app, sn, input, prop, value, timestamp, quality)
	local node = self._nodes[sn]
	if not node or not node.vars then
		log:error("Unknown sn", sn)
		return
	end
	local var = node.vars[input]
	if var and prop == 'value' then
		set_var_value(var, value, timestamp, quality)
	end
end

local function create_handler(self)
	return end

function app:connect_proc()
	local client = self._client
	local r, err = pcall(client.Connect, client, "opc.tcp://127.0.0.1:4840/freeopcua/server/")
	print(r, err)
end

function app:start()
	local client = opcua.Client.new(false)
	self._sys:fork(function() self:connect_proc() end)
	self._client = client
	self._nodes = {}
	self._api:set_handler({
		on_add_device = function(app, sn, props)
			return self:on_add_device(app, sn, props)
		end,
		on_del_device = function(app, sn)
			print(app, sn)
		end,
		on_mod_device = function(app, sn, props)
			return self:on_mod_device(app, sn, props)
		end,
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			return self:on_input(app, sn, input, prop, value, timestamp, quality)
		end,
	}, true)

	return true
end

function app:close(reason)
	print(self._name, reason)
	self._client:Disconnect()
	self._client = nil
end

function app:run(tms)
	return 1000
end

return app

