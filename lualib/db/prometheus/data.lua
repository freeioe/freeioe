local class = require 'middleclass'

local data = class('db.prometheus.data')

function data:initialize()
	self._list = {}
end

function data:add_metric(metric)
	table.insert(self._list, metric)
end

function data:encode(auto_clean)
	local data = {}
	for _, v in ipairs(self._list) do
		local lines = v:encode(auto_clean)
		table.move(lines, 1, #lines, #data, data)
	end

	return table.concat(data, '\n')
end

return data
