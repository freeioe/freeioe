local skynet = require 'skynet'
local class = require 'middleclass'

local metric = class('db.prometheus')

function metric:initialize(name, labels, typ, help)
	assert(name)
	self._name = name
	self._labels = labels or {}
	self._typ = typ
	self._help = help
	self._values = {}
end

function metric:metric_name()
	return self._name
end

function metric:labels()
	return self._labels
end

function metric:set_label(name, value)
	self._labels[name] = value
end

function metric:push_value(value, timestamp)
	if type(value) == 'string' then
		value = assert(tonumber(value))
	end
	table.insert(self._values, {
		value = value,
		timestamp = timestamp or skynet.time()
	})
end

function metric:values()
	return self._values
end

function metric:clean()
	self._values = {}
end

function metric:_encode_value(value, timestamp)
	local val = tostring(value)
	local ts = math.floor(timestamp * 1000)
	local labels = self._labels
	local llist = {}
	for k, v in pairs(labels) do
		local val = v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
		llist[#llist + 1] = string.format('%s="%s"', k, val)
	end
	if #llist == 0 then
		return string.format('%s %s %d', self._name, val, ts)
	end
	return string.format("%s{%s} %s %d", self._name, table.concat(llist, ','), val, ts)
end

function metric:_encode_values()
	local list = {}
	for _, v in ipairs(self._values) do
		list[#list + 1] = self:_encode_value(v.value, v.timestamp)
	end
	return list
end

function metric:encode(auto_clean)
	local lines = self:_encode_values()
	if self._help then
		table.insert(lines, 1, '# HELP '..self._name..' '..self._help)
	end
	if self._typ then
		table.insert(lines, 1, '# TYPE '..self._name..' '..self._typ)
	end
	if auto_clean then
		self:clean()
	end
	return lines
end

function metric:decode(lines)
	assert(nil, "Not implemented")
end

return metric
