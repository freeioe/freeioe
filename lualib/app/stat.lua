local skynet = require 'skynet'
local ioe = require 'ioe'
local log = require 'utils.log'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'

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

function stat:_cleanup()
	self._readonly = true
	self._stat_chn = nil
	self._app_name = nil
	self._name = nil
	self._sn = nil
	self._api = nil
end

function stat:cleanup()
	if self._readonly then
		return
	end
	local sn = self._sn

	self:_cleanup()
end

function stat:get(prop)
	return dc.get('STAT', self._sn, self._name, prop)
end

function stat:reset(prop)
	return self:set(prop, 0)
end

function stat:inc(prop, value)
	assert(not self._readonly, "This is not created device statistics")
	assert(prop and value)
	if not self._stat_map[prop] then
		return nil, "Statistics property is not valid. "..prop
	end

	value = value + self:get(prop)

	dc.set('STAT', self._sn, self._name, prop, value)
	self._stat_chn:publish(self._app_name, self._sn, self._name, prop, value, ioe.time())
	return true
end

function stat:set(prop, value)
	assert(not self._readonly, "This is not created device statistics")
	assert(prop and value)
	if not self._stat_map[prop] then
		return nil, "Statistics property is not valid. "..prop
	end

	dc.set('STAT', self._sn, self._name, prop, value)
	self._stat_chn:publish(self._app_name, self._sn, self._name, prop, value, ioe.time())
	return true
end

return stat
