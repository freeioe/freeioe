local skynet = require 'skynet'
local ioe = require 'ioe'
local log = require 'utils.log'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local stat_api = require 'app.stat'

local device = class("APP_MGR_DEV_API")

--- Do not call this directly, but throw the api.lua
function device:initialize(api, sn, props, guest, secret)
	self._api = api
	self._sn = sn
	self._props = props
	self._app_src = api._app_name
	self._secret = secret
	if guest then
		self._app_name = dc.get('DEV_IN_APP', sn) or api._app_name
		self._props = dc.get('DEVICES', sn) or {}
	else
		self._app_name = api._app_name
	end
	self._data_chn = api._data_chn
	self._ctrl_chn = api._ctrl_chn
	self._comm_chn = api._comm_chn
	self._event_chn = api._event_chn
	self._guest = guest

	self._inputs_map = {}
	for _, t in ipairs(props.inputs or {}) do
		assert(self._inputs_map[t.name] == nil, "Duplicated input name ["..t.name.."] found")
		self._inputs_map[t.name] = t
	end
	self._stats = {}

	if not guest then
		dc.set('DEVICES', sn, props)
		dc.set('DEV_IN_APP', sn, self._app_name)
	end
end

function device:_cleanup()
	self._guest = true
	self._app_name = nil
	self._app_src = nil
	self._sn = nil
	self._props = nil
	self._inputs_map = nil
	self._data_chn = nil
	self._ctrl_chn = nil
	self._comm_chn = nil
	self._api = nil
	self._cov = nil
end

function device:cleanup()
	if self._guest then
		return
	end
	if self._cov then
		self._cov:stop()
	end
	for _, s in ipairs(self._stats) do
		s:cleanup()
	end
	self._stats = {}

	local sn = self._sn
	local props = self._props

	self._api._devices[sn] = nil

	dc.set('DEVICES', sn, nil)
	dc.set('DEV_IN_APP', sn, nil)
	dc.set('INPUT', sn, nil)
	dc.set('OUTPUT', sn, nil)

	log.trace("DELETE DEVICE", self._app_name, sn, props)
	self._data_chn:publish('del_device', self._app_name, sn, props)

	self:_cleanup()
end

local function valid_prop_name(name)
	return nil == string.find(name, "[^%w_]")
end

function device:mod(inputs, outputs, commands)
	assert(not self._guest, "Device permission denined!")
	for _, v in ipairs(inputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid input name") end
	for _, v in ipairs(outputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid output name") end
	for _, v in ipairs(commands or {}) do assert(valid_prop_name(v.name), v.name.." is not valid command name") end

	self._props.inputs = inputs or self._props.inputs
	self._props.outputs = outputs or self._props.outputs
	self._props.commands = commands or self._props.commands

	self._inputs_map = {}
	for _, t in ipairs(inputs or {}) do
		self._inputs_map[t.name] = t
	end
	dc.set('DEVICES', self._sn, self._props)
	if self._cov then
		self._cov:clean()
	end

	self._data_chn:publish('mod_device', self._app_name, self._sn, self._props)
	return true
end

function device:add(inputs, outputs, commands)
	assert(not self._guest, "Device permission denined!")
	for _, v in ipairs(inputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid input name") end
	for _, v in ipairs(outputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid output name") end
	for _, v in ipairs(commands or {}) do assert(valid_prop_name(v.name), v.name.." is not valid command name") end

	local org_inputs = self._props.inputs
	for _, v in ipairs(inputs or {}) do
		org_inputs[#org_inputs + 1] = v
	end
	local org_outputs = self._props.outputs
	for _, v in ipairs(outputs or {}) do
		org_outputs[#org_outputs + 1] = v
	end
	local org_commands = self._props.commands
	for _, v in ipairs(commands or {}) do
		org_commands[#org_commands + 1] = v
	end
	self:mod(org_inputs, org_outputs, org_commands)
end

function device:get_input_prop(input, prop)
	local t = dc.get('INPUT', self._sn, input, prop)
	if t then
		return t.value, t.timestamp, t.quality
	end
end

function device:_publish_input(input, prop, value, timestamp, quality)
	return self._data_chn:publish('input', self._app_name, self._sn, input, prop, value, timestamp, quality)
end

function device:set_input_prop(input, prop, value, timestamp, quality)
	assert(input and prop and value, "Input/Prop/Value are required as not nil value")
	if self._guest then
		assert(self._secret, "Device permission denined!")
		local secret = dc.get("DEVICE_SECRET", self._sn)
		assert(secret, "Device permission denined!")
		assert(secret == self._secret, "Device secret is not correct")
	end

	local value = value
	local it = self._inputs_map[input]
	if not it then
		return nil, "Property "..input.." does not exits in device "..self._sn
	else
		if it.vt == 'int' then
			value = math.floor(tonumber(value))
		elseif it.vt == 'string' then
			value = tostring(value)
		else
			value = tonumber(value)
		end
	end
	if not value then
		return nil, "Invalid value"
	end

	local timestamp = timestamp or ioe.time()
	local quality = quality or 0

	dc.set('INPUT', self._sn, input, prop, {value=value, timestamp=timestamp, quality=quality})
	if not self._cov then
		self:_publish_input(input, prop, value, timestamp, quality)
	else
		self._cov:handle(input..'/'..prop, value, timestamp, quality)
	end
	return true
end

function device:set_input_prop_emergency(input, prop, value, timestamp, quality)
	assert(input and prop and value, "Input/Prop/Value are required as not nil value")
	if self._guest then
		assert(self._secret, "Device permission denined!")
		local secret = dc.get("DEVICE_SECRET", self._sn)
		assert(secret, "Device permission denined!")
		assert(secret == self._secret, "Device secret is not correct")
	end

	local value = value
	local it = self._inputs_map[input]
	if not it then
		return nil, "Property "..input.." does not exits in device "..self._sn
	else
		if it.vt == 'int' then
			value = math.floor(tonumber(value))
		elseif it.vt == 'string' then
			value = tostring(value)
		else
			value = tonumber(value)
		end
	end
	if not value then
		return nil, "Invalid value"
	end

	local timestamp = timestamp or ioe.time()
	local quality = quality or 0

	self._data_chn:publish('input_em', self._app_name, self._sn, input, prop, value, timestamp, quality)

	return self:set_input_prop(input, prop, value, timestamp, quality)
end

function device:get_output_prop(output, prop)
	local t = dc.get('OUTPUT', self._sn, output, prop)
	return t.value, t.timestamp
end

function device:set_output_prop(output, prop, value, timestamp, priv)
	local priv = priv or '__NO_RESULT__CALL__'
	for _, v in ipairs(self._props.outputs or {}) do
		if v.name == output then
			local timestamp = timestamp or ioe.time()
			dc.set('OUTPUT', self._sn, output, prop, {value=value, timestamp=timestamp})
			self._ctrl_chn:publish('output', self._app_src, self._app_name, self._sn, output, prop, value, timestamp, priv)
			return true
		end
	end
	return nil, "Output property "..output.." does not exits in device "..self._sn
end

function device:send_command(command, param, priv)
	local priv = priv or '__NO_RESULT__CALL__'
	for _, v in ipairs(self._props.commands or {}) do
		if v.name == command then
			self._ctrl_chn:publish("command", self._app_src, self._app_name, self._sn, command, param, priv)
			return true
		end
	end
	return nil, "Command "..command.." does not exits in device "..self._sn
end

function device:sn()
	return self._sn
end

function device:list_props()
	return self._props
end

function device:list_inputs(data_cb)
	local inputs = self._props.inputs or {}
	local input_vals = dc.get('INPUT', self._sn) or {}
	for _, v in ipairs(inputs) do
		for prop, val in pairs(input_vals[v.name] or {}) do
			data_cb(v.name, prop, val.value, val.timestamp, val.quality)
		end
	end
end

function device:cov(opt)
	assert(not self._guest, "Device permission denined!")
	if not opt then
		self._cov = nil
	else
		local COV = require 'cov'

		self._cov = COV:new(function(key, value, timestamp, quality)
			local input, prop = string.match(key, '^(.+)/([^/]+)')
			assert(input and prop, "Bug found matching input/prop key")
			return self:_publish_input(input, prop, value, timestamp, quality)
		end, opt)

		self._cov:start()
	end
end

function device:data()
	return dc.get('INPUT', self._sn)
end

function device:flush_data()
	assert(not self._guest, "Device permission denined!")
	return self:list_inputs(function(input, prop, value, timestamp, quality)
		self._data_chn:publish('input', self._app_name, self._sn, input, prop, value, timestamp, quality)
	end)
end

function device:dump_comm(dir, ...)
	assert(not self._guest, "Device permission denined!")
	return self._comm_chn:publish(self._app_name, self._sn, dir, ioe.time(), ...)
end

function device:fire_event(level, type_, info, data, timestamp)
	assert(not self._guest, "Device permission denined!")
	return self._api:_fire_event(self._sn, level, type_, info, data, timestamp)
end

function device:stat(name)
	assert(not self._guest, "Device permission denined!")
	local stat = stat_api:new(self._api, self._sn, name, self._guest)
	self._stats[#self._stats + 1] = stat
	return stat
end

---
-- Share this device with specified device secret
--   Then the application instance who knows this secret
--   will be able to write input prop to this device
--   secret is nil will disable shares
function device:share(secret)
	self._secret = secret
	dc.set('DEVICE_SECRET', self._secret)
end

return device
