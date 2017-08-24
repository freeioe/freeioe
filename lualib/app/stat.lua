local skynet = require 'skynet'
local log = require 'utils.log'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'

local stat = class("APP_MGR_DEV_API")

local standard_props = {'status', 'packets_in', 'packets_out', 'packets_error', 'bytes_in', 'bytes_out', 'bytes_error'}

function stat:initialize(api, sn, readonly)
	self._api = api
	self._sn = sn
	if readonly then
		self._app_name = dc.get('DEV_IN_APP', sn) or api._app_name
	else
		self._app_name = api._app_name
	end
	self._stat_chn = api._stat_chn
	self._readonly = readonly
	self._stat_list = {}
	self._stat_map = {}
end

function stat:_cleanup()
	self._readonly = true
	self._stat_chn = nil
	self._app_name = nil
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

function stat:add(stat)
	table.insert(self._stat_list, stat)
	self._stat_map[stat] = true
end

function stat:del(stat)
	self._stat_map[stat] = nil
	for i, v in ipairs(self._stat_list) do
		if v = stat then
			table.remove(self._stat_list, i)
		end
	end
end

function stat:get(stat, prop)
	return dc.get('STAT', self._sn, input, prop)
end

function stat:set(stat, prop, value)
	assert(not self._readonly, "This is not created device")
	assert(stat and prop and value)
	if not standard_map[prop] then
		return nil, "Statistics property is not valid. "..prop
	end

	if not self._stat_map[stat] then
		return nil, "Statistics "..stat.." does not exits in device "..self._sn
	end

	dc.set('STAT', self._sn, stat, prop, value)
	self._stat_chn:publish(self._app_name, self._sn, stat, prop, value, skynet.time())
	return true
end

function stat:list()
	return self._stat_list
end

return stat
