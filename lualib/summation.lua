local class = require 'middleclass'
local cjson = require 'cjson.safe'
local utimer = require 'utils.timer'

local sum = class('Continue_Count_LIB')

local SPAN_KEY = '__SPAN_KEY'

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
	if span == 'never' then
		return 'NEVER'
	end
	return nil, "Incorrect time span"
end

local function calc_save_time(now, save_span)
	assert(now and save_span)
	local save_time = math.floor(math.floor(now / save_span) * save_span)
	return save_time
end

local function migrate_from_v1(opt)
	local path = (opt.path or '/var/run')..'/ioe_sum_'
	local filename = path..opt.key..'_'..opt.span

	local f, err = io.open(filename, 'r')
	if not f then
		return nil, err
	end

	local str = f:read('*a')
	f:close()

	local value = cjson.decode(str) or {}
	if value == cjson.null then
		value = {}
	end

	local new_value = {}
	for k, v in pairs(value) do
		if string.sub(k, 1, 2) ~= '__' then
			new_value[k] = {
				base = value['__'..k],
				value = v,
				delta = 0
			}
		end
	end
	return new_value
end

function sum:initialize(opt)
	self._value = {}
	if opt.file then
		opt.save_span = opt.save_span or 60 * 5
		--- loading from file
		local path = (opt.path or '/var/run')..'/ioe_sum_v2_'
		local filename = path..opt.key..'_'..opt.span
		self._span_key = assert(get_span_key(opt.span))
		self._filename = filename 
		self._last_save = calc_save_time(os.time(), opt.save_span)

		local f, err = io.open(filename, 'r')
		if f then
			local str = f:read('*a')
			f:close()

			self._value = cjson.decode(str) or {}
			if self._value == cjson.null then
				self._value = {}
			end
			-- for origin version that does not have span key in saved file
			if not self._value[SPAN_KEY] then
				self._value[SPAN_KEY] = self._span_key
			end
			-- Check for span key 
			if self._value[SPAN_KEY] ~= self._span_key then
				self:reset()
			end
		else
			self._value = migrate_from_v1(opt) or {}
		end
	end
	self._opt = opt
	self._opt_on_reset = opt.on_reset

	self._timer = utimer:new(function()
		self:check_save()
	end, 60, true) --- every minute
	self._timer:start()
end

function sum:__gc()
	self._timer:stop()
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
	local val = self._value[key] or { base = 0, value = 0, delta = 0 }
	val.value = val.value + value

	self._value[key] = val

	self:check_save()
end

function sum:set(key, value)
	local val = self._value[key] or { base = 0, value = 0, delta = 0 }

	if value >= val.value then
		val.value = value
	else
		val.delta = val.value - val.base + val.delta --- The current value
		val.base = 0
		val.value = value
	end

	self._value[key] = val

	self:check_save()
end

function sum:get(key)
	local val = self._value[key] or { base = 0, value = 0, delta = 0 }
	return val.value - val.base + val.delta
end

function sum:reset()
	if self._opt_on_reset then
		pcall(self._opt_on_reset)
	end
	for k, v in pairs(self._value) do
		if k ~= SPAN_KEY then
			v.base = v.value
			v.delta = 0
		end
	end
	self._value[SPAN_KEY] = self._span_key
end

function sum:set_reset_cb(cb)
	self._opt_on_reset = cb
end

function sum:save()
	if not self._filename then
		return nil, "File open failure!!"
	end

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
