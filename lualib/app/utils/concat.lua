local class = require 'middleclass'
local ioe = require 'ioe'
local skynet = require 'skynet'
local cancelable_timeout = require 'cancelable_timeout'

local concat = class('APP_UTILS_CONCAT')

function concat:initialize(func, need_all, delay, timeout)
	assert(func, "Calculate function missing")

	self._calc = func
	self._need_all = need_all
	self._delay = delay
	self._timeout = timeout

	self._source = {}
end

function concat:add(key, default, delay, timeout)
	self._source[key] = {
		name = key,
		default = default,
		value = default,
		delay = delay,
		timeout = timeout,
		last = ioe.time()
	}
end

function concat:update(key, value, timestamp, quality)
	local timestamp = timestamp or ioe.time()
	local quality = quality == nil and 0 or quality

	local item = self._source[key]
	assert(item)

	item.value = quality == 0 and value or item.default
	item.timestamp = timestamp
	item.last = ioe.time()

	local delay = item.delay or self._delay

	if delay > 0 then
		if self._delay_exec_cancel then
			self._delay_exec_cancel()
		end
		self._delay_exec_cancel = cancelable_timeout(delay, function()
			self._delay_exec_cancel = nil
			self:call_calc()
		end)
	end
end

function concat:call_calc()
	--print('call_calc')
	local values = {}
	local now = ioe.time()
	for k, v in pairs(self._source) do
		local timeout = v.timeout or self._timeout
		if timeout and v.value and (now - v.last) * 1000 > timeout then
			v.value = v.default
		end

		if self._need_all and not v.value then
			return
		end

		values[k] = v.value
	end

	self._calc(values)
end

return concat
