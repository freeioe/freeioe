---
-- Timer utils module
-- Added in API_VER:6
--

local skynet = require 'skynet'
local class = require 'middleclass'

local timer = class('FreeIOE_Lib_Utils_Timer')

---
-- span --- Time span in seconds
--
function timer:initialize(cb, span, integral_time)
	self._cb = cb
	self._span = span
	self._integral_time = integral_time
	self._closed = nil
end

function timer:start()
	self._closed = nil
	skynet.fork(function()
		--- Set the last time
		local span = self._span
		local now = skynet.time()
		local last_cb_time = now
		if self._integral_time then
			last_cb_time = (now // span) * span
		end

		--- Next time
		local next_cb_time = last_cb_time + self._span

		while not self._stop do
			skynet.sleep(math.floor((next_cb_time - skynet.time()) * 100), self)
			if self._stop then
				break
			end

			last_cb_time = next_cb_time
			next_cb_time = next_cb_time + self._span
			if self._cb then
				local r, err = xpcall(self._cb, debug.traceback, last_cb_time)
				if not r then
					skynet.error('utils.timer error:', err)
				end
			end
		end
		self._closed = true
	end)
end

function timer:stop()
	if not self._stop then
		self._stop = true
		skynet.wakeup(self)
		assert(self._closed)
	end
end

return timer
