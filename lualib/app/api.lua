local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local dev_api = require 'app.device'

local api = class("APP_MGR_API")

function api:initialize(app_name, mgr_snax, cloud_snax)
	self._app_name = app_name
	self._mgr_snax = mgr_snax or snax.uniqueservice('appmgr')
	self._cloud_snax = cloud_snax or snax.uniqueservice('cloud')
	self._devices = {}
end

function api:cleanup()
	for sn, dev in pairs(self._devices) do
		self:del_device(dev)
	end
	self._devices = {}
end

function api:data_dispatch(channel, source, cmd, app, sn, ...)
	--log.trace('Data Dispatch', channel, source, cmd, app, sn, ...)
	local f = self._handler['on_'..cmd]
	if f then
		return f(app, sn, ...)
	else
		log.trace('No handler for '..cmd)
	end
end

function api:ctrl_dispatch(channel, source, ctrl, app, sn, ...)
	if app ~= self._app_name then
		return
	end

	--log.trace('Ctrl Dispatch', channel, source, ctrl, app, sn, ...)
	local f = self._handler['on_'..ctrl]
	if f then
		return f(app, sn, ...)
	else
		log.trace('No handler for '..ctrl)
	end
end

function api:comm_dispatch(channel, source, app, sn, ...)
	--log.trace('Comm Dispatch', channel, source, ...)
	local f = self._handler.on_comm
	if f then
		return f(app, sn, ...)
	else
		log.trace('No handler for on_comm')
	end
end

function api:stat_dispatch(channel, source, app, sn, ...)
	--log.trace('Stat Dispatch', channel, source, ...)
	local f = self._handler.on_stat
	if f then
		return f(app, sn, ...)
	else
		log.trace('No handler for on_stat')
	end
end

function api:event_dispatch(channel, source, app, sn, ...)
	--log.trace('Event Dispatch', channel, source, ...)
	local f = self._handler.on_event
	if f then
		return f(app, sn, ...)
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
		if handler.on_ctrl or handler.on_output or handler.on_command then
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
		manufacturer = "Bamboo IOT",
		series = "Unknown",
		link = "http://unknown",
	}
end

function api:add_device(sn, meta, inputs, outputs, commands)
	assert(sn, "Device Serial Number is required")
	valid_device_meta(meta or default_meta())
	meta.app = self._app_name
	meta.inst = meta.inst or meta.name
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

-- Get readonly device object to access input / fire command / output
function api:get_device(sn)
	local props = dc.get('DEVICES', sn)
	if not props then
		return nil, string.format("Device %s does not exits", sn)
	end
	return dev_api:new(self, sn, props, true)
end

-- Applicaiton control
function api:send_ctrl(app, ctrl, params)
	self._ctrl_chn:publish('ctrl', self._app_name, app, cmd, params)
end

function api:_dump_comm(sn, dir, ...)
	assert(sn)
	return self._comm_chn:publish(self._app_name, sn, dir, skynet.time(), ...)
end

--[[
-- Get application configuration 
--]]
function api:get_conf(sn)
	return dc.get('APPS', self._app_name, 'conf')
end

--[[
-- Set application configuration
--]]
function api:set_conf(sn, conf)
	return dc.set('APPS', self._app_name, 'conf')
end

return api
