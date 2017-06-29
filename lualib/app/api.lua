local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local class = require 'middleclass'
local mc = require 'skynet.multicast'

local api = class("APP_MGR_API")

function api:initialize(app_name, mgr_snax, wrap_snax)
	self._app_name = app_name
	self._mgr_snax = mgr_snax
	self._wrap_snax = wrap_snax

	self._data_chn = mc.new ({
		channel = mgr_snax.req.get_channel('data'),
		dispatch = function(channel, source, ...)
			self.data_dispatch(self, channel, source, ...)
		end
	})
	self._data_chn:subscribe()

	self._ctrl_chn = mc.new ({
		channel = mgr_snax.req.get_channel('ctrl'),
		dispatch = function(channel, source, ...)
			self.ctrl_dispatch(self, channel, source, ...)
		end
	})
	self._ctrl_chn:subscribe()

	self._comm_chn = mc.new ({
		channel = mgr_snax.req.get_channel('comm'),
		dispatch = function(channel, source, ...)
			self.comm_dispatch(self, channel, source, ...)
		end
	})
	self._comm_chn:subscribe()
end

function api:data_dispatch(channel, source, ...)
	log.trace('Data Dispatch', channel, source, ...)
end

function api:ctrl_dispatch(channel, source, ...)
	log.trace('Ctrl Dispatch', channel, source, ...)
end

function api:comm_dispatch(channel, source, ...)
	log.trace('Comm Dispatch', channel, source, ...)
end

--[[
-- Set devices update callback
-- @param app: default is "*"
--]]
function api:set_device_cb(app, func)
end

--[[
-- List devices
-- @param app: default is "*"
--]]
function api:list_devices(app)
end

function api:add_device(sn, props)
	self._data_chn:publish(sn, props)
end

function api:del_device(sn)
end

function api:get_device(sn)
end

function api:set_prop_cb(sn, func)
end

function api:get_prop_value(sn, prop, type)
end

function api:set_prop_value(sn, prop, type, value)
end

--[[
-- generate device serial number
--]]
function api:gen_sn()
end

--[[
-- Get device configuration string by device serial number(sn)
--]]
function api:get_conf(sn)
end

--[[
-- Set device configuration string
--]]
function api:set_conf(sn, conf)
end

return api
