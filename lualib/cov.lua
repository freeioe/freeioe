local class = require 'middleclass'

local cov = class("_ChangeOnValue_LIB")

function cov:initialize(opt)
	local opt = opt or {}
	opt.float_threshold = 0.000001
	opt.try_convert_string = true
	self._opt = opt
	self._retained_map = {}
end

function cov:clean()
	self._retained_map = {}
end

function cov:handle_number(key, value, cb, threshold)
	local org_value = self._retained_map[key]
	if not org_value then
		self._retained_map[key] = value
		return cb(key, value)
	end
	if math.tointeger(value) then
		if value ~= org_value then
			self._retained_map[key] = value
			return cb(key, value)
		end
	else
		if math.abs(value - org_value) > threshold then
			self._retained_map[key] = value
			return cb(key, value)
		end
	end
end

function cov:handle(key, value, cb, threshold)
	local opt = self._opt
	local threshold = threshold or opt.float_threshold
	-- 
	if type(value) == 'number' then
		return self:handle_number(key, value, cb, threshold)
	else
		if opt.try_convert_string then
			local nval = tonumber(value)
			if nval then
				return self:handle_number(key, value, cb, threshold)
			end
		end
		self._retained_map[key] = value
		return cb(key, value)
	end
end

return cov
