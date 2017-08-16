local class = require 'middleclass'

local cov = class("_ChangeOnValue_LIB")

function cov:initialize(opt)
	local opt = opt or {}

	opt.float_threshold = 0.000001
	opt.try_convert_string = true
	if opt.ttl then
		assert(opt.ttl > 0)
	end

	self._opt = opt
	self._retained_map = {}
end

function cov:clean()
	self._retained_map = {}
end

function cov:handle_number(cb, key, value, timestamp, quality)
	local opt = self._opt
	local org_value = self._retained_map[key]
	local new_value = {value, timestamp, quality}
	self._retained_map[key] = new_value

	if not org_value then
		return cb(key, value, timestamp, quality)
	end
	if opt.ttl and ((timestamp - org_value[2]) >= opt.ttl) then
		return cb(key, value, timestamp, quality)
	end
	if org_value[3] ~= quality then
		return cb(key, value, timestamp, quality)
	end
	if math.abs(value - org_value[1]) > opt.float_threshold then
		return cb(key, value, timestamp, quality)
	end

	self._retained_map[key] = org_value
end

function cov:handle_string(cb, key, value, timestamp, quality)
	local opt = self._opt
	local org_value = self._retained_map[key]
	local new_value = {value, timestamp, quality}
	self._retained_map[key] = new_value

	if not org_value then
		return cb(key, value, timestamp, quality)
	end
	if opt.ttl and ((timestamp - org_value[2]) >= opt.ttl) then
		return cb(key, value, timestamp, quality)
	end
	if org_value[3] ~= quality then
		return cb(key, value, timestamp, quality)
	end
	if value ~= org_value[1] then
		return cb(key, value, timestamp, quality)
	end

	self._retained_map[key] = org_value
end

function cov:handle(cb, key, value, timestamp, quality)
	assert(cb and key and value and timestamp)
	local opt = self._opt
	if opt.disable then
		return cb(key, value, timestamp, quality)
	end

	if type(value) == 'number' then
		return self:handle_number(cb, key, value, timestamp, quality)
	else
		if opt.try_convert_string then
			local nval = tonumber(value)
			if nval then
				return self:handle_number(cb, key, value, timestamp, quality)
			end
		end
		return self:handle_string(cb, key, value, timestamp, quality)
	end
end

function cov:fire_snapshot(cb)
	for key, v in pairs(self._retained_map) do
		cb(key, table.unpack(v))
	end
end

function cov:timer(now)
	local opt = self._opt
	for key, v in pairs(self._retained_map) do
		if math.abs(now - v[2]) > (opt.ttl * 2) then
			self._retained_map[key] = nil
		end
	end
end

return cov
