---
-- Device Statistics Module
--
-- This module provides statistics tracking and reporting for devices.
-- It manages counters and ratios for communication performance monitoring.
--
-- Standard Statistics Properties:
--   status - Current device status
--   success_ratio - Success operation ratio (percentage)
--   error_ratio - Error operation ratio (percentage)
--   packets_in - Total packets received
--   packets_out - Total packets sent
--   packets_error - Total packet errors
--   bytes_in - Total bytes received
--   bytes_out - Total bytes sent
--   bytes_error - Total byte errors
---

local skynet = require 'skynet'
local ioe = require 'ioe'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'

---
-- Statistics Class
--
-- Manages device statistics with automatic persistence and
-- multicast publishing of updates.
---
local stat = class("APP_MGR_DEV_API")

local standard_props = {
	'status',
	'success_ratio',
	'error_ratio',
	'packets_in',
	'packets_out',
	'packets_error',
	'bytes_in',
	'bytes_out',
	'bytes_error'
}

---
-- Initialize statistics instance for a device
-- @param api: parent API object
-- @param sn: device serial number
-- @param name: statistics name (e.g., 'comm', 'data')
-- @param readonly: true if this is a guest (read-only) statistics object
---
function stat:initialize(api, sn, name, readonly)
	self._api = api
	self._sn = sn
	self._name = name
	if readonly then
		self._app_name = dc.get('DEV_IN_APP', sn) or api._app_name
	else
		self._app_name = api._app_name
	end
	self._stat_chn = api._stat_chn
	self._readonly = readonly
	self._stat_map = {}
	for _,v in ipairs(standard_props) do
		self._stat_map[v] = true
		dc.set('STAT', self._sn, self._name, v, 0)
	end
end

---
-- Internal cleanup of statistics references
---
function stat:_cleanup()
	self._readonly = true
	self._stat_chn = nil
	self._app_name = nil
	self._name = nil
	self._sn = nil
	self._api = nil
end

---
-- Cleanup statistics object
-- For owner statistics, clears internal references
---
function stat:cleanup()
	if self._readonly then
		return
	end
	local sn = self._sn

	self:_cleanup()
end

---
-- Get statistics property value
-- @param prop: property name
-- @return: property value or nil if not found
---
function stat:get(prop)
	return dc.get('STAT', self._sn, self._name, prop)
end

---
-- Reset statistics property to zero
-- @param prop: property name
-- @return: set result
---
function stat:reset(prop)
	return self:set(prop, 0)
end

---
-- Increment statistics property by value
-- @param prop: property name
-- @param value: increment amount (must be positive)
-- @return: true on success, nil and error message on failure
---
function stat:inc(prop, value)
	assert(not self._readonly, "Device statistics owner issue")
	assert(prop and value)
	if not self._stat_map[prop] then
		return nil, string.format("Statistics property [%s] is not valid. ", prop)
	end

	value = value + self:get(prop)

	dc.set('STAT', self._sn, self._name, prop, value)
	self._stat_chn:publish(self._app_name, self._sn, self._name, prop, value, ioe.time())
	return true
end

---
-- Set statistics property to specific value
-- @param prop: property name
-- @param value: new property value
-- @return: true on success, nil and error message on failure
---
function stat:set(prop, value)
	assert(not self._readonly, "Device statistics owner issue")
	assert(prop and value)
	if not self._stat_map[prop] then
		return nil, string.format("Statistics property [%s] is not valid. ", prop)
	end

	dc.set('STAT', self._sn, self._name, prop, value)
	self._stat_chn:publish(self._app_name, self._sn, self._name, prop, value, ioe.time())
	return true
end

return stat
