local class = require 'middleclass'
local cjson = require 'cjson.safe'

local sum = class('Continue_Count_LIB')

local function get_filename(key, span)
	assert(key and span)
	if span == 'year' then
		return key .. '_' .. os.date('%Y')
	end
	if span == 'month' then
		return key .. '_' .. os.date('%Y_%m')
	end
	if span == 'day' then
		return key .. '_' .. os.date('%Y_%m_%d')
	end
	if span == 'hour' then
		return key .. '_' .. os.date('%Y_%m_%d_%H')
	end
	return nil, "Incorrect time span"
end

function sum:initialize(opt)
	self._value = {}
	if opt.file then
		--- loading from file
		local path = (opt.path or '/var/run')..'/ioe_sum_'
		local filename = assert(get_filename(opt.key, opt.span))
		self._filename = filename
		self._path = path
		self._last_save = os.time()
		opt.save_span = opt.save_span or 60 * 5

		local f, err = io.open(path..filename, 'r')
		if f then
			local str = f:read('*a')
			print("CC:LOAD", str)
			self._value = cjson.decode(str)
			f:close()
		end
	end
	self._opt = opt
end

function sum:__gc()
	self:save()
end

function sum:add(key, value)
	local org = self._value[key] or 0
	local __value = self._value['__'..key]
	print("CC:ADD", key, value, org, __value)

	if __value and value < __value then
		self._value['__'..key] = nil
	end
	self._value[key] = org  + value
end

function sum:set(key, value)
	local org = self._value[key] or 0
	local __value = self._value['__'..key]
	print("CC:SET", key, value, org, __value)

	if os.time() - self._last_save > self._opt.save_span then
		self:save()
		self._last_save = os.time()
	end

	if value >= org then
		if __value and value > __value then
			value = value - __value
		end
		self._value[key] = value
	else
		if __value and value < __value then
			self._value['__'..key] = nil
		end
		self._value[key] = org + value
	end
end

function sum:get(key)
	return self._value[key] or 0
end

function sum:reset()
	for k, v in pairs(self._value) do
		if string.sub(k, 1, 2) ~= '__' then
			self._value['__'..k] = self._value['__'..k] + v
			self._value[k] = 0
		end
	end
end

function sum:save()
	if not self._filename then
		return nil, "File open failure!!"
	end
	print("CC:SAVE", cjson.encode(self._value))

	local new_filename = get_filename(self._opt.key, self._opt.span)
	local value = self._value
	if new_filename ~= self._filename then
		self._filename = new_filename
		self:reset()
	end

	local f, err = io.open(self._path..self._filename, 'w+')
	if f then
		f:write(cjson.encode(value))
		f:close()
		return true
	end
	return nil, err
end

return sum
