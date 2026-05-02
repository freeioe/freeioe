---
-- Device API Module
--
-- This module provides the device management interface for applications.
-- Devices represent I/O points, communication channels, or data sources
-- that applications can create, manage, and interact with.
---

local skynet = require 'skynet'
local ioe = require 'ioe'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local stat_api = require 'app.stat'

---
-- Device API Class
--
-- Represents a device instance with inputs, outputs, and commands.
-- Provides methods for data handling, communication dumping, and device management.
---
local device = class("APP_MGR_DEV_API")

---
-- Enable new batch update mode
-- When enabled, input updates are batched and published periodically
-- instead of immediately for better performance
---
local USE_NEW_BATCH_UPDATE = 1

---
-- Initialize device instance
-- @param api: parent API object
-- @param sn: device serial number
-- @param props: device properties table
--   - name: device name
--   - desc: device description
--   - inputs: array of input definitions {name, desc, unit}
--   - outputs: array of output definitions
--   - commands: array of command definitions
-- @param guest: true if this is a guest (read-only) device
-- @param secret: device secret key
---
--- Do not call this directly, but throw the api.lua
function device:initialize(api, sn, props, guest, secret)
	self._api = api
	self._logger = api._logger
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

	if USE_NEW_BATCH_UPDATE then
		self._data_cache_map = {}
		self._data_cache_map_token = {}
		skynet.fork(function()
			while not self._close_wait do
				skynet.sleep(300, self._data_cache_map_token)
				if #self._data_cache_map > 0 then
					skynet.sleep(5) -- wait more data coming
					local data = self._data_cache_map
					self._data_cache_map = {}
					self._data_chn:publish('input_batch', self._app_name, self._sn, data)
				end
			end
			skynet.wakeup(self._close_wait)
		end)
	end
end

---
-- Internal cleanup of device references
-- Clears all internal references to allow garbage collection
---
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

---
-- Cleanup and remove device from system
-- Stops all services, removes device from datacenter, publishes deletion event
---
function device:cleanup()
	if self._guest then
		return
	end
	if USE_NEW_BATCH_UPDATE and self._data_cache_map_token then
		self._close_wait = {}
		-- wakeup just mark this token is to be wakeup
		skynet.wakeup(self._data_cache_map_token)
		skynet.sleep(200, self._close_wait)
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

	self._logger:trace("DELETE DEVICE", self._app_name, sn, props)
	self._data_chn:publish('del_device', self._app_name, sn, props)

	self:_cleanup()
end

---
-- Validate property name format
-- @param name: property name string
-- @return: true if valid (contains only word characters and underscores)
---
local function valid_prop_name(name)
	return nil == string.find(name, "[^%w_]")
end

---
-- Modify device inputs, outputs, and commands
-- Replaces existing definitions with new ones
-- @param inputs: array of input definitions {name, desc, unit}
-- @param outputs: array of output definitions
-- @param commands: array of command definitions
-- @return: true on success
---
function device:mod(inputs, outputs, commands)
	assert(not self._guest, "Device permission denied!")
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

---
-- Add new inputs, outputs, and commands to existing device
-- Appends to existing definitions instead of replacing
-- @param inputs: array of input definitions to add
-- @param outputs: array of output definitions to add
-- @param commands: array of command definitions to add
---
function device:add(inputs, outputs, commands)
	assert(not self._guest, "Device permission denied!")
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

---
-- Get input property value from datacenter
-- @param input: input name
-- @param prop: property name (value, timestamp, quality)
-- @return: value, timestamp, quality or nil if not found
---
function device:get_input_prop(input, prop)
	local t = dc.get('INPUT', self._sn, input, prop)
	if t then
		return t.value, t.timestamp, t.quality
	end
end

---
-- Internal method to publish input value to data channel
-- Uses batch mode if enabled, otherwise publishes immediately
-- @param input: input name
-- @param prop: property name
-- @param value: property value
-- @param timestamp: value timestamp
-- @param quality: value quality flag
---
function device:_publish_input(input, prop, value, timestamp, quality)
	assert(timestamp)
	if not USE_NEW_BATCH_UPDATE then
		return self._data_chn:publish('input', self._app_name, self._sn, input, prop, value, timestamp, quality)
	end
	--- New mode for data fires
	self._data_cache_map[#self._data_cache_map + 1] = { input, prop, value, timestamp, quality }
	skynet.wakeup(self._data_cache_map_token)
end

---
-- Set multiple input properties in batch
-- Accepts either table format {input, prop, value, timestamp, quality}
-- or object format {{input=, prop=, value=, timestamp=, quality=}, ...}
-- @param ...: variable arguments of input data
-- @return: true on success, nil and error message on failure
---
function device:set_input_prop_batch(...)
	local inputs = {...}
	if #inputs == 0 then
		return nil, 'No input data'
	end

	if inputs[1].input then
		local map_inputs = {}
		for _, v in ipairs(inputs) do
			map_inputs[#map_inputs + 1] = {v.input, v.prop, v.value, v.timestamp or ioe.time(), v.quality or 0 }
		end
		inputs = map_inputs
	else
		for _, v in ipairs(inputs) do
			inputs[4] = inputs[4] or ioe.time()
			inputs[5] = inputs[5] or 0
		end
	end

	if self._cov then
		local changed_inputs = self._cov:handle_batch(inputs)
		if #changed_inputs == 0 then
			return true -- all input data are not changed
		end
		inputs = changed_inputs
	end

	-- Copy inputs into cached map then wakeup data_cache_map_token
	table.move(inputs, 1, #inputs, #self._data_cache_map + 1, #self._data_cache_map)
	skynet.wakeup(self._data_cache_map_token)
	-- TODO: Should we sleep here?

	return true
end

---
-- Set a single input property value
-- Validates input name and performs type conversion based on input definition
-- @param input: input name
-- @param prop: property name (typically 'value')
-- @param value: property value
-- @param timestamp: optional timestamp (defaults to current time)
-- @param quality: optional quality flag (defaults to 0)
-- @return: true on success, nil and error message on failure
---
function device:set_input_prop(input, prop, value, timestamp, quality)
	assert(input and prop and (value ~= nil), "Input/Prop/Value are required as not nil value")
	if self._guest then
		assert(self._secret, "Device permission denied!")
		local secret = dc.get("DEVICE_SECRET", self._sn)
		assert(secret, "Device permission denied!")
		assert(secret == self._secret, "Device secret is not correct")
	end

	local value = value
	if type(value) == 'boolean' then
		value = value and 1 or 0
	end

	local it = self._inputs_map[input]
	if not it then
		return nil, "Property "..input.." does not exist in device "..self._sn
	else
		if prop == 'value' then
			if it.vt == 'int' then
				value = math.floor(tonumber(value))
			elseif it.vt == 'string' then
				value = tostring(value)
			else
				value = tonumber(value)
			end
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

---
-- Set input property value with emergency flag
-- Publishes an emergency event before setting the value
-- @param input: input name
-- @param prop: property name
-- @param value: property value
-- @param timestamp: optional timestamp
-- @param quality: optional quality flag
-- @return: true on success, nil and error message on failure
---
function device:set_input_prop_emergency(input, prop, value, timestamp, quality)
	assert(input and prop and value, "Input/Prop/Value are required as not nil value")
	if self._guest then
		assert(self._secret, "Device permission denied!")
		local secret = dc.get("DEVICE_SECRET", self._sn)
		assert(secret, "Device permission denied!")
		assert(secret == self._secret, "Device secret is not correct")
	end

	local value = value
	local it = self._inputs_map[input]
	if not it then
		return nil, "Property "..input.." does not exist in device "..self._sn
	else
		if prop == 'value' then
			if it.vt == 'int' then
				value = math.floor(tonumber(value))
			elseif it.vt == 'string' then
				value = tostring(value)
			else
				value = tonumber(value)
			end
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

---
-- Get output property value from datacenter
-- @param output: output name
-- @param prop: property name
-- @return: value, timestamp
---
function device:get_output_prop(output, prop)
	local t = dc.get('OUTPUT', self._sn, output, prop)
	return t.value, t.timestamp
end

---
-- Set output property value
-- Publishes to control channel for applications to handle
-- @param output: output name
-- @param prop: property name
-- @param value: property value
-- @param timestamp: optional timestamp
-- @param priv: optional private data for result correlation
-- @return: true on success, nil and error message on failure
---
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
	return nil, "Output property "..output.." does not exist in device "..self._sn
end

---
-- Send command to device
-- Publishes to control channel for applications to handle
-- @param command: command name
-- @param param: command parameter
-- @param priv: optional private data for result correlation
-- @return: true on success, nil and error message on failure
---
function device:send_command(command, param, priv)
	local priv = priv or '__NO_RESULT__CALL__'
	for _, v in ipairs(self._props.commands or {}) do
		if v.name == command then
			self._ctrl_chn:publish("command", self._app_src, self._app_name, self._sn, command, param, priv)
			return true
		end
	end
	return nil, "Command "..command.." does not exist in device "..self._sn
end

---
-- Get device serial number
-- @return: device serial number string
---
function device:sn()
	return self._sn
end

---
-- Get application instance name that created this device
-- @return: application name
---
function device:app_name()
	return self._app_name
end

---
-- Get device properties table
-- @return: table containing device metadata, inputs, outputs, commands
---
function device:list_props()
	return self._props
end

---
-- List all input values and pass to callback
-- @param data_cb: callback function(input, prop, value, timestamp, quality)
---
function device:list_inputs(data_cb)
	local inputs = self._props.inputs or {}
	local input_vals = dc.get('INPUT', self._sn) or {}
	for _, v in ipairs(inputs) do
		for prop, val in pairs(input_vals[v.name] or {}) do
			data_cb(v.name, prop, val.value, val.timestamp, val.quality)
		end
	end
end

---
-- Configure Change-of-Value (COV) monitoring for inputs
-- When enabled, only publishes input values that actually change
-- @param opt: COV options table or nil to disable
---
function device:cov(opt)
	assert(not self._guest, "Device permission denied!")
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

---
-- Get all input data for this device
-- @return: table of input values from datacenter
---
function device:data()
	return dc.get('INPUT', self._sn)
end

---
-- Flush all input data to data channel
-- Forces immediate publication of all current input values
---
function device:flush_data()
	assert(not self._guest, "Device permission denied!")
	return self:list_inputs(function(input, prop, value, timestamp, quality)
		self._data_chn:publish('input', self._app_name, self._sn, input, prop, value, timestamp, quality)
	end)
end

---
-- Dump communication data to comm channel
-- @param dir: direction (send/recv)
-- @param ...: communication data
-- @return: publish result
---
function device:dump_comm(dir, ...)
	assert(not self._guest, "Device permission denied!")
	return self._comm_chn:publish(self._app_name, self._sn, dir, ioe.time(), ...)
end

---
-- Fire an event for this device
-- @param level: event severity level
-- @param type_: event type string
-- @param info: event description
-- @param data: optional event data table
-- @param timestamp: optional event timestamp
-- @return: event fire result
---
function device:fire_event(level, type_, info, data, timestamp)
	assert(not self._guest, "Device permission denied!")
	return self._api:_fire_event(self._sn, level, type_, info, data, timestamp)
end

---
-- Create a statistics counter for this device
-- @param name: statistics name (e.g., packets_in, bytes_out)
-- @return: statistics object
---
function device:stat(name)
	-- assert(not self._guest, "Device permission denied!")
	local stat = stat_api:new(self._api, self._sn, name, self._guest)
	self._stats[#self._stats + 1] = stat
	return stat
end

---
-- Share this device with other applications using a secret key
-- Applications with the correct secret can write input values to this device
-- @param secret: secret key string or nil to disable sharing
---
function device:share(secret)
	self._secret = secret
	dc.set('DEVICE_SECRET', self._secret)
end

return device
