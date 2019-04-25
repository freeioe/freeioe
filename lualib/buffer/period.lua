local class = require 'middleclass'
local skynet = require 'skynet'

local pb = class("_PERIOD_CONSUMER_LIB")

-- Period in ms
function pb:initialize(period, size)
	assert(period and size)
	self._period = period
	self._max_size = size
	self._buf = {}
	self._cb = nil
end

function pb:handle(...)
	self._buf[#self._buf + 1] = {...}
	--print('pb size', self:size())

	if not self._max_size then
		return
	end

	if #self._buf > self._max_size then
		if self._full_cb then
			local data = self._buf[1]
			self._full_cb(table.unpack(data))
		end
		table.remove(self._buf, 1)	
	end
end

function pb:fire_all(cb)
	local cb = cb or self._cb
	assert(cb)

	local buf = self._buf
	if #buf <= 0 then
		return true
	end

	if cb(buf) then
		self._buf = {}
		return true
	end
	return false
end

function pb:reinit(period, size)
	self._period = period or self._period
	self._max_size = size or self._max_size
end

function pb:size()
	return #self._buf
end

function pb:period()
	return self._period
end

function pb:max_size()
	return self._max_size
end

function pb:start(cb, full_cb)
	assert(cb)
	self._stop = nil
	self._cb = cb
	self._full_cb = full_cb
	skynet.fork(function()
		while not self._stop do
			self:fire_all(cb)
			--print(math.floor(self._period / 10))
			skynet.sleep(math.floor(self._period / 10), self)
		end
		skynet.wakeup(self)
	end)
end

function pb:stop()
	if not self._stop then
		self._stop = true
		skynet.wait(self)
	end
end

return pb
