local skynet = require 'skynet'
local class = require 'middleclass'

local data = class('db.siridb.data')

function data:initialize()
	self._list = {}
end

function data:encode(time_precision, auto_clean)
	local data = {}
	for k, v in pairs(self._list) do
		data[k] = v:encode(time_precision, auto_clean)
	end
	return data
end

function data:add_series(name, series)
	assert(name)
	assert(series)
	assert(self._list[name] == nil)
	self._list[name] = series
end

function data:list()
	return self._list
end

return data
