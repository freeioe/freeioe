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

local function create_var(idx, devobj, input, device)
	local var, err = devobj:getChild(input.name)
	if var then
		var:setDescription(opcua.LocalizedText.new('zh_CN', input.desc))
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

	return devobj:addVariable(opcua.NodeId.new(idx, 0), input.name, attr)
end

local function set_var_value(var, value, timestamp, quality)
	var:setValue(opcua.Variant.new(value))

	--[[
	local val = opcua.DataValue.new(opcua.Variant.new(value))
	val.status = quality
	local tm = opcua.DateTime.fromUnixTime(math.floor(timestamp)) +  math.floor((timestamp%1) * 100) * 100000
	val.sourceTimestamp = tm
	--var.dataValue = val
	var:setDataValue(val)
	]]--
end

local function create_handler(app)
	local api = app._api
	local server = app._server
	local log = app._log
	local idx = app._idx
	local nodes = {}
	return {
		on_add_device = function(app, sn, props)
			-- 
			local objects = server:getObjectsNode()
			local id = opcua.NodeId.new(idx, sn)
			local device = api:get_device(sn)

			local devobj, err = objects:getChild(idx..":"..sn)
			if not r or not devobj then
				local attr = opcua.ObjectAttributes.new()
				attr.displayName = opcua.LocalizedText.new("zh_CN", "Device "..sn)
				devobj, err = objects:addObject(opcua.NodeId.new(idx, sn), sn, attr)
				if not devobj then
					log:warning('Create device object failed, error', devobj)
					return
				end
			end

			local node = nodes[sn] or {
				device = device,
				devobj = devobj,
				vars = {}
			}
			local vars = node.vars
			for i, input in ipairs(props.inputs) do
				local var = vars[input.name]
				if not var then
					vars[input.name] = create_var(idx, devobj, input, device)
				else
					var:setDescription(opcua.LocalizedText.new('zh_CN', input.desc))
				end
			end
			nodes[sn] = node
		end,
		on_del_device = function(app, sn)
			local node = nodes[sn]
			if node then
				node:deleteNode(true)
			end
		end,
		on_mod_device = function(app, sn, props)
			local node = nodes[sn]
			if not node or not node.vars then
			end
			local vars = node.vars
			for i, input in ipairs(props.inputs) do
				local var = vars[input.name]
				if not var then
					vars[input.name] = create_var(idx, node.devobj, input, node.device)
				else
					var:setDescription(opcua.LocalizedText.new('zh_CN', input.desc))
				end
			end
		end,
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			local node = nodes[sn]
			if not node or not node.vars then
				log:error("Unknown sn", sn)
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
	local Level_Funcs = {}
	Level_Funcs[opcua.LogLevel.TRACE] = assert(self._log.trace)
	Level_Funcs[opcua.LogLevel.DEBUG] = assert(self._log.debug)
	Level_Funcs[opcua.LogLevel.INFO] = assert(self._log.info)
	Level_Funcs[opcua.LogLevel.WARNING] = assert(self._log.warning)
	Level_Funcs[opcua.LogLevel.ERROR] = assert(self._log.error)
	Level_Funcs[opcua.LogLevel.FATAL] = assert(self._log.fatal)
	Category_Names = {}
	Category_Names[opcua.LogCategory.NETWORK] = "network"
	Category_Names[opcua.LogCategory.SECURECHANNEL] = "channel"
	Category_Names[opcua.LogCategory.SESSION] = "session"
	Category_Names[opcua.LogCategory.SERVER] = "server"
	Category_Names[opcua.LogCategory.CLIENT] = "client"
	Category_Names[opcua.LogCategory.USERLAND] = "userland"
	Category_Names[opcua.LogCategory.SECURITYPOLICY] = "securitypolicy"

	self._logger = function(level, category, ...)
		Level_Funcs[level](self._log, Category_Names[category], ...)
	end
	opcua.setLogger(self._logger)

	local server = opcua.Server.new()

	server.config:setServerURI("urn:://opcua.symid.com")

	local id = self._sys:id()
	local idx = server:addNamespace("http://iot.symid.com/"..id)

	self._server = server
	self._idx = idx
	self._api:set_handler(create_handler(self), true)
	
	server:startup()

	self._log:notice("Started!!!!")
	return true
end

function app:close(reason)
	self._server:shutdown()
	self._server = nil
end

function app:run(tms)
	while self._server.running do
		local ms = self._server:run_once(false)
		self._sys:sleep(10)
	end
	print('XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX')

	return 1000
end

return app

