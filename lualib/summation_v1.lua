local class = require 'middleclass'
local cjson = require 'cjson.safe'

local sum = class('Continue_Count_LIB')

local function get_span_key(span)
	if span == 'year' then
		return os.date('%Y')
	end
	if span == 'month' then
		return os.date('%Y_%m')
	end
	if span == 'day' then
		return os.date('%Y_%m_%d')
	end
	if span == 'hour' then
		return os.date('%Y_%m_%d_%H')
	end
	if span == 'minute' then
		return os.date('%Y_%m_%d_%H_%M')
	end
	return nil, "Incorrect time span"
end

local function calc_save_time(now, save_span)
	assert(now and save_span)
	local save_time = math.floor(math.floor(now / save_span) * save_span)
	--print('calc_save_time', now, save_time)
	return save_time
end

function sum:initialize(opt)
	self._value = {}
	if opt.file then
		--- loading from file
		local path = (opt.path or '/var/run')..'/ioe_sum_'
		local filename = path..opt.key..'_'..opt.span
		self._span_key = assert(get_span_key(opt.span))
		self._filename = filename 
		self._last_save = calc_save_time(os.time(), opt.save_span)
		opt.save_span = opt.save_span or 60 * 5

		local f, err = io.open(filename, 'r')
		if f then
			local str = f:read('*a')
			--print("CC:LOAD", str)
			self._value = cjson.decode(str)
			--print("CC:LOAD", str, cjson.encode(self._value))
			f:close()
		end
	end
	self._opt = opt
end

function sum:__gc()
	self:save()
end

function sum:check_save()
	local now = os.time()
	if now - self._last_save >= self._opt.save_span then
		self:save()
		self._last_save = calc_save_time(now, self._opt.save_span)
	end
end

function sum:add(key, value)
	self:check_save()

	local org = self._value[key] or 0
	self._value[key] = org  + value

	-- Reset __value
	self._value['__'..key] = nil
end

function sum:set(key, value)
	self:check_save()

	local org = self._value[key] or 0
	local __value = self._value['__'..key]
	--print("CC:SET", key, value, org, __value)

	if value >= org then
		if __value and value <  __value + org then
			--print("1 CC:Reset __Value", key, value, org, __value)
			self._value['__'..key] = nil
			__value = nil
		end
		--- 值持续增加中
		if __value and value >= __value + org then
			value = value - __value
		end
		self._value[key] = value
	else
		--- 值被重置了
		if __value and value < __value + org then
			--print("2 CC:Reset __Value", key, value, org, __value)
			self._value['__'..key] = nil
		end
		self._value[key] = org + value
	end
end

function sum:get(key)
	return self._value[key] or 0
end

function sum:reset()
	local new_value = {}
	for k, v in pairs(self._value) do
		if string.sub(k, 1, 2) ~= '__' then
			local __value = self._value['__'..k] or 0
			--print('RESET', k, v, __value)
			new_value['__'..k] = __value + v
			new_value[k] = 0
		end
	end
	self._value = new_value
	--print('RESET Result', cjson.encode(new_value))
end

function sum:save()
	if not self._filename then
		return nil, "File open failure!!"
	end
	--print("CC:SAVE", cjson.encode(self._value))

	local new_span_key = get_span_key(self._opt.span)
	local value = self._value
	if new_span_key ~= self._span_key then
		self._span_key = new_span_key
		self:reset()
	end

	local f, err = io.open(self._filename, 'w+')
	if f then
		f:write(cjson.encode(value))
		f:close()
		return true
	end
	return nil, err
end

return sum
