local skynet = require 'skynet'
local class = require 'middleclass'

local series = class('db.siridb.series')

local _MAP_TS = {
	s = 1,
	ms = 1000,
	us = 1000000,
	ns = 1000000000
}

function series:initialize(name)
	self._name = name
	self._values = {}
end

function series:series_name()
	return self._name
end

function series:clean()
	self._values = {}
end

function series:encode(time_precision, auto_clean)
	local ts = _MAP_TS[time_precision]

	local data = {}
	for k, v in ipairs(self._values) do
		data[#data + 1] = {math.floor(v[1] * ts), v[2]}
	end
	if auto_clean then
		self:clean()
	end
	return data
end

function series:push_value(value, timestamp)
	table.insert(self._values, {timestamp or skynet.time(), value})
end

function series:values()
	return self._values
end

return series
