local skynet = require 'skynet'
local snax = require 'skynet.snax'
local ioe = require 'ioe'
local log = require 'utils.log'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local dev_api = require 'app.device'
local app_event = require 'app.event'
local threshold_buffer = require 'buffer.threshold'

local api = class("APP_MGR_API")

function api:initialize(app_name, mgr_snax, cloud_snax)
	self._app_name = app_name
	self._mgr_snax = mgr_snax or snax.queryservice('appmgr')
	self._cloud_snax = cloud_snax or snax.queryservice('cloud')
	self._devices = {}
	self._event_fire_buf = nil
end

function api:cleanup()
	for sn, dev in pairs(self._devices) do
		self:del_device(dev)
	end
	self._devices = {}
end

function api:data_dispatch(channel, source, cmd, app, ...)
	--log.trace('Data Dispatch', channel, source, cmd, app, ...)
	local f = self._handler['on_'..cmd]
	if f then
		return f(app, ...)
	else
		log.trace('No handler for '..cmd)
	end
end

function api:ctrl_dispatch(channel, source, ctrl, app_src, app, ...)
	if app ~= self._app_name then
		--- Skip the destination is other application one
		return
	end

	log.trace('Ctrl Dispatch', channel, source, ctrl, app_src, app, ...)
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
				self._ctrl_chn:publish(ctrl..'_result', app, app_src, priv, table.unpack(results, 2))
			end
		end, ...)
	else
		log.trace('No handler for '..ctrl)
	end
end

function api:comm_dispatch(channel, source, app, ...)
	--log.trace('Comm Dispatch', channel, source, ...)
	local f = self._handler.on_comm
	if f then
		return f(app, ...)
	else
		log.trace('No handler for on_comm')
	end
end

function api:stat_dispatch(channel, source, app, ...)
	--log.trace('Stat Dispatch', channel, source, ...)
	local f = self._handler.on_stat
	if f then
		return f(app, ...)
	else
		log.trace('No handler for on_stat')
	end
end

function api:event_dispatch(channel, source, app, ...)
	--log.trace('Event Dispatch', channel, source, ...)
	local f = self._handler.on_event
	if f then
		return f(app, ...)
	else
		log.trace('No handler for on_event')
	end
end

function api:set_handler(handler, watch_data)
	self._handler = handler
	local mgr = self._mgr_snax

	if handler then
		self._data_chn = mc.new ({
			channel = mgr.req.get_channel('data'),
			dispatch = function(channel, source, ...)
				self:data_dispatch(channel, source, ...)
			end
		})
		if watch_data then
			self._data_chn:subscribe()
		end
	else
		if self._data_chn then
			self._data_chn:unsubscribe()
			self._data_chn = nil
		end
	end

	if handler then
		self._ctrl_chn = mc.new ({
			channel = mgr.req.get_channel('ctrl'),
			dispatch = function(channel, source, ...)
				self:ctrl_dispatch(channel, source, ...)
			end
		})
		if handler.on_ctrl or handler.on_output or handler.on_command or
			handler.on_ctrl_result or handler.on_output_result or handler.on_command_result then
			self._ctrl_chn:subscribe()
		end
	else
		if self._ctrl_chn then
			self._ctrl_chn:unsubscribe()
			self._ctrl_chn = nil
		end
	end

	if handler then
		self._comm_chn = mc.new ({
			channel = mgr.req.get_channel('comm'),
			dispatch = function(channel, source, ...)
				self:comm_dispatch(channel, source, ...)
			end
		})
		if handler.on_comm then
			self._comm_chn:subscribe()
		end
	else
		if self._comm_chn then
			self._comm_chn:unsubscribe()
			self._comm_chn = nil
		end
	end

	if handler then
		self._stat_chn = mc.new({
			channel = mgr.req.get_channel('stat'),
			dispatch = function(channel, source, ...)
				self:stat_dispatch(channel, source, ...)
			end
		})
		if handler.on_stat then
			self._stat_chn:subscribe()
		end
	else
		if self._stat_chn then
			self._stat_chn:unsubscribe()
			self._stat_chn = nil
		end
	end

	if handler then
		self._event_chn = mc.new({
			channel = mgr.req.get_channel('event'),
			dispatch = function(channel, source, ...)
				self:event_dispatch(channel, source, ...)
			end
		})
		if handler.on_event then
			self._event_chn:subscribe()
		end
	else
		if self._event_chn then
			self._event_chn:unsubscribe()
			self._event_chn = nil
		end
	end
	self:_set_event_threshold(20)
end

--[[
-- List devices
--]]
function api:list_devices()
	return dc.get('DEVICES')
end

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

function api:default_meta()
	return {
		name = "Unknown",
		description = "Unknown device",
		manufacturer = "FreeIOE",
		series = "Unknown",
		link = "http://device.freeioe.org/device?name=",
	}
end

local function valid_device_sn(sn)
	--return nil == string.find(sn, '%s')
	return nil == string.find(sn, "[^%w_%-%.]")
end

local function valid_prop_name(name)
	return nil == string.find(name, "[^%w_]")
end

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

	local props = {meta = meta, inputs = inputs, outputs = outputs, commands = commands}
	dev = dev_api:new(self, sn, props)
	self._devices[sn] = dev
	self._data_chn:publish('add_device', self._app_name, sn, props)
	return dev
end

function api:del_device(dev)
	dev:cleanup()
	return true
end

-- Get device object to access input, fire command and write output
--  With correct secret will be able to write the input
function api:get_device(sn, secret)
	assert(sn, "Device Serial Number is required!")
	local props = dc.get('DEVICES', sn)
	if not props then
		return nil, string.format("Device %s does not exits", sn)
	end
	return dev_api:new(self, sn, props, true, secret)
end

-- Applicaiton control
function api:send_ctrl(app, ctrl, params, priv)
	self._ctrl_chn:publish('ctrl', self._app_name, app, ctrl, params, priv)
end

function api:_dump_comm(sn, dir, ...)
	assert(sn)
	return self._comm_chn:publish(self._app_name, sn, dir, ioe.time(), ...)
end

function api:_set_event_threshold(count_per_min)
	assert(count_per_min > 0 and count_per_min < 128)
	self._event_fire_buf = threshold_buffer:new(60, count_per_min, function(...)
		return self._event_chn:publish(...)
	end, function(...)
		log.error('Event threshold reached:', ...)
	end)
end

function api:_fire_event(sn, level, type_, info, data, timestamp)
	assert(sn and level and type_ and info)
	local type_ = app_event.type_to_string(type_)
	return self._event_fire_buf:push(self._app_name, sn, level, type_, info, data or {}, timestamp or ioe.time())
end

return api
