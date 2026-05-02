---
-- Application API Module
--
-- This module provides the core API interface for FreeIOE applications.
-- It manages device lifecycle, handles data/control/communication dispatching,
-- and provides integration with the application manager.
---

local skynet = require 'skynet'
local snax = require 'skynet.snax'
local ioe = require 'ioe'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local dev_api = require 'app.device'
local app_event = require 'app.event'
local app_logger = require 'app.logger'
local threshold_buffer = require 'buffer.threshold'

---
-- Application API Class
--
-- Main class that provides the interface for applications to interact
-- with FreeIOE system services including device management, data handling,
-- and event processing.
---
local api = class("APP_MGR_API")

---
-- Initialize the API instance
-- @param app_name: application name
-- @param mgr_snax: appmgr service handle (optional, will query if nil)
-- @param logger: logger instance (optional, creates default if nil)
---
function api:initialize(app_name, mgr_snax, logger)
	self._app_name = app_name
	self._mgr_snax = mgr_snax or snax.queryservice('appmgr')
	self._devices = {}
	self._event_fire_buf = nil
	self._logger = logger or app_logger:new(app_name)
end

---
-- Cleanup API resources
-- Removes all devices and closes handler
---
function api:cleanup()
	self:close_handler()
	for sn, dev in pairs(self._devices) do
		self:del_device(dev)
	end
	self._devices = {}
end

---
-- Split batch input data into individual calls
-- @param f: handler function
-- @param app: application name
-- @param sn: device serial number
-- @param datas: table of data batches
-- @return: true
---
function api:input_batch_split(f, app, sn, datas)
	for _, v in ipairs(datas) do
		f(app, sn, table.unpack(v))
	end
	return true
end

---
-- Dispatch data channel messages to appropriate handlers
-- @param channel: channel name
-- @param source: message source
-- @param cmd: command type (input, output, command, input_batch)
-- @param app: application name
-- @param ...: additional arguments
-- @return: handler result or nil if no handler found
---
function api:data_dispatch(channel, source, cmd, app, ...)
	-- self._logger:trace('Data Dispatch', channel, source, cmd, app, ...)
	local f = self._handler['on_'..cmd]
	if f then
		return f(app, ...)
	else
		if cmd == 'input_batch' then
			-- self._logger:trace('Data Batch Dispatch', channel, source, cmd, app, 'fallback to on_input')
			local f = self._handler['on_input']
			if f then
				return self:input_batch_split(f, app, ...)
			end
		end
		self._logger:trace('No handler for '..cmd)
	end
end

---
-- Dispatch control channel messages to appropriate handlers
-- Handles synchronous commands with automatic result publishing
-- @param channel: channel name
-- @param source: message source
-- @param ctrl: control command type
-- @param app_src: source application
-- @param app: target application
-- @param ...: command arguments
---
function api:ctrl_dispatch(channel, source, ctrl, app_src, app, ...)
	if app ~= self._app_name then
		--- Skip the destination is other application one
		return
	end

	self._logger:trace('Ctrl Dispatch', channel, source, ctrl, app_src, app, ...)
	local f = self._handler['on_'..ctrl]
	if f then
		--- check if this is result dispatch
		if string.match(ctrl, '(.+)_result$') then
			skynet.fork(function(...)
				f(app_src, ...)
			end, ...)

			return
		end

		--- priv is the end parameters
		local priv = select(-1, ...)

		--- create an new coroutine to execute the command/output/ctrl and wait for result
		skynet.fork(function(...)
			local results = table.pack(xpcall(f, debug.traceback, app_src, ...))
			if not results[1] then
				self._ctrl_chn:publish(ctrl..'_result', app, app_src, priv, false, results[2])
			else
				if results[2] == nil then
					-- Table unpack loses nil returns
					results[2] = false
				end
				self._ctrl_chn:publish(ctrl..'_result', app, app_src, priv, table.unpack(results, 2))
			end
		end, ...)
	else
		self._logger:trace('No handler for '..ctrl)
	end
end

---
-- Dispatch communication data to handler
-- @param channel: channel name
-- @param source: message source
-- @param app: application name
-- @param ...: communication data
---
function api:comm_dispatch(channel, source, app, ...)
	--self._logger:trace('Comm Dispatch', channel, source, ...)
	local f = self._handler.on_comm
	if f then
		return f(app, ...)
	else
		self._logger:trace('No handler for on_comm')
	end
end

---
-- Dispatch statistics data to handler
-- @param channel: channel name
-- @param source: message source
-- @param app: application name
-- @param ...: statistics data
---
function api:stat_dispatch(channel, source, app, ...)
	--self._logger:trace('Stat Dispatch', channel, source, ...)
	local f = self._handler.on_stat
	if f then
		return f(app, ...)
	else
		self._logger:trace('No handler for on_stat')
	end
end

---
-- Dispatch event data to handler
-- @param channel: channel name
-- @param source: message source
-- @param app: application name
-- @param ...: event data
---
function api:event_dispatch(channel, source, app, ...)
	--self._logger:trace('Event Dispatch', channel, source, ...)
	local f = self._handler.on_event
	if f then
		return f(app, ...)
	else
		self._logger:trace('No handler for on_event')
	end
end

---
-- Close all multicast channels and cleanup handlers
---
function api:close_handler()
	if self._data_chn then
		self._data_chn:unsubscribe()
		self._data_chn = nil
	end
	if self._ctrl_chn then
		self._ctrl_chn:unsubscribe()
		self._ctrl_chn = nil
	end
	if self._comm_chn then
		self._comm_chn:unsubscribe()
		self._comm_chn = nil
	end
	if self._stat_chn then
		self._stat_chn:unsubscribe()
		self._stat_chn = nil
	end
	if self._event_chn then
		self._event_chn:unsubscribe()
		self._event_chn = nil
	end
end

---
-- Set handler for application callbacks and subscribe to channels
-- @param handler: table containing callback functions (on_input, on_output, on_command, etc.)
-- @param watch_data: boolean, if true subscribe to data channel for watching all device data
---
function api:set_handler(handler, watch_data)
	self._handler = handler
	if not self._handler then
		return api:close_handler()
	end

	local mgr = self._mgr_snax

	self._data_chn = self._data_chn or mc.new ({
		channel = mgr.req.get_channel('data'),
		dispatch = function(channel, source, ...)
			self:data_dispatch(channel, source, ...)
		end
	})
	if watch_data then
		self._data_chn:subscribe()
	end

	self._ctrl_chn = self._ctrl_chn or mc.new ({
		channel = mgr.req.get_channel('ctrl'),
		dispatch = function(channel, source, ...)
			self:ctrl_dispatch(channel, source, ...)
		end
	})
	if handler.on_ctrl or handler.on_output or handler.on_command or
		handler.on_ctrl_result or handler.on_output_result or handler.on_command_result then

		self._ctrl_chn:subscribe()
	end

	self._comm_chn = self._comm_chn or mc.new ({
		channel = mgr.req.get_channel('comm'),
		dispatch = function(channel, source, ...)
			self:comm_dispatch(channel, source, ...)
		end
	})
	if handler.on_comm then
		self._comm_chn:subscribe()
	end

	self._stat_chn = self._stat_chn or mc.new({
		channel = mgr.req.get_channel('stat'),
		dispatch = function(channel, source, ...)
			self:stat_dispatch(channel, source, ...)
		end
	})
	if handler.on_stat then
		self._stat_chn:subscribe()
	end

	self._event_chn = self._event_chn or mc.new({
		channel = mgr.req.get_channel('event'),
		dispatch = function(channel, source, ...)
			self:event_dispatch(channel, source, ...)
		end
	})
	if handler.on_event then
		self._event_chn:subscribe()
	end
	self:_set_event_threshold(20)
end

---
-- List all devices in the system
-- @param with_data: boolean, if true includes current input/output values
-- @return: table of devices with optional data values
---
function api:list_devices(with_data)
	local devs = dc.get('DEVICES')
	if not with_data then
		return devs
	end

	-- Get dc snapshot
	local inputs = dc.get('INPUT') or {}
	local outputs = dc.get('OUTPUT') or {}
	local dev_in_apps = dc.get('DEV_IN_APP') or {}

	for sn, props in pairs(devs or {}) do
		props.app_name = dev_in_apps[sn]

		local vals = inputs[sn] or {}
		for _, input in ipairs(props.inputs or {}) do
			input.props = vals[input.name]
		end
		local ovals = outputs[sn] or {}
		for _, output in ipairs(props.outputs or {}) do
			output.props = ovals[output.name]
		end
	end
	-- Return all devices with their data
	return devs
end

---
-- Validate device metadata table
-- @param meta: table containing device metadata
-- @raises: assertion error if required fields are missing
---
function valid_device_meta(meta)
	local meta_assert = function(name)
		assert(meta[name], "Device "..name.." is required in meta info!")
	end
	assert(meta, 'Device meta is required!')
	meta_assert("name")
	meta_assert("description")
	meta_assert("manufacturer")
	meta_assert("series")
	meta_assert("link")
end

---
-- Get default device metadata template
-- @return: table with default device metadata fields
---
function api:default_meta()
	return {
		name = "Unknown",
		description = "Unknown device",
		manufacturer = "FreeIOE",
		series = "Unknown",
		link = "http://device.freeioe.org/device?name=",
	}
end

---
-- Validate device serial number format
-- @param sn: device serial number string
-- @return: true if valid, false if contains invalid characters
---
local function valid_device_sn(sn)
	--return nil == string.find(sn, '%s')
	return nil == string.find(sn, "[^%w_%-%.]")
end

---
-- Validate property/input/output name format
-- @param name: property name string
-- @return: true if valid, false if contains invalid characters
---
local function valid_prop_name(name)
	return nil == string.find(name, "[^%w_]")
end

---
-- Add a new device to the application
-- @param sn: device serial number (unique identifier)
-- @param meta: table with device metadata (name, description, manufacturer, series, link)
-- @param inputs: array of input definitions {name, desc, unit}
-- @param outputs: array of output definitions {name, desc, unit}
-- @param commands: array of command definitions {name, desc}
-- @return: device object for accessing the device
---
function api:add_device(sn, meta, inputs, outputs, commands)
	assert(self._handler, "Cannot add device before initialize your API handler by calling set_handler")
	assert(sn and meta, "Device Serial Number and Meta Information is required!")
	assert(valid_device_sn(sn), "Invalid sn: "..sn)
	for _, v in ipairs(inputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid input name") end
	for _, v in ipairs(outputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid output name") end
	for _, v in ipairs(commands or {}) do assert(valid_prop_name(v.name), v.name.." is not valid command name") end

	valid_device_meta(meta or default_meta())
	meta.app_inst = self._app_name
	meta.app = dc.get('APPS', self._app_name, 'name') or 'FreeIOE'
	meta.inst = meta.inst or meta.name -- 实际设备实例名称, 如:BMS #2,PLC #2
	local dev = self._devices[sn]
	if dev then
		return dev
	end

	inputs = (inputs and #inputs > 0) and inputs or nil
	outputs = (outputs and #outputs > 0) and outputs or nil
	commands = (commands and #commands > 0) and commands or nil

	local props = {meta = meta, inputs = inputs, outputs = outputs, commands = commands}
	dev = dev_api:new(self, sn, props)
	self._devices[sn] = dev
	self._data_chn:publish('add_device', self._app_name, sn, props)
	return dev
end

---
-- Delete a device from the application
-- @param dev: device object to delete
-- @return: true
---
function api:del_device(dev)
	dev:cleanup()
	return true
end

---
-- Get device object to access inputs, outputs, and commands
-- With correct secret will be able to write input values
-- @param sn: device serial number
-- @param secret: optional secret for write access
-- @return: device object or nil, error message if not found
---
function api:get_device(sn, secret)
	assert(sn, "Device Serial Number is required!")
	local props = dc.get('DEVICES', sn)
	if not props then
		return nil, string.format("Device %s does not exist", sn)
	end
	return dev_api:new(self, sn, props, true, secret)
end

---
-- Send control command to another application
-- @param app: target application name
-- @param ctrl: control command type
-- @param params: command parameters
-- @param priv: private data for result correlation
---
function api:send_ctrl(app, ctrl, params, priv)
	self._ctrl_chn:publish('ctrl', self._app_name, app, ctrl, params, priv)
end

---
-- Dump communication data to comm channel
-- @param sn: device serial number
-- @param dir: direction (send/recv)
-- @param ...: communication data to dump
-- @return: publish result
---
function api:_dump_comm(sn, dir, ...)
	assert(sn)
	return self._comm_chn:publish(self._app_name, sn, dir, ioe.time(), ...)
end

---
-- Set event firing threshold limit (events per minute)
-- @param count_per_min: maximum events allowed per minute (1-127)
---
function api:_set_event_threshold(count_per_min)
	assert(count_per_min > 0 and count_per_min < 128)
	self._event_fire_buf = threshold_buffer:new(60, count_per_min, function(...)
		return self._event_chn:publish(...)
	end, function(...)
		self._logger:error('Event threshold reached:', ...)
	end)
end

---
-- Fire an event to the event channel
-- @param sn: device serial number
-- @param level: event severity level (debug, info, warning, error, fatal)
-- @param type_: event type string
-- @param info: event description string
-- @param data: optional event data table
-- @param timestamp: optional event timestamp (defaults to current time)
-- @return: buffer push result
---
function api:_fire_event(sn, level, type_, info, data, timestamp)
	assert(sn and level and type_ and info)
	local type_ = app_event.type_to_string(type_)
	return self._event_fire_buf:push(self._app_name, sn, level, type_, info, data or {}, timestamp or ioe.time())
end

return api
