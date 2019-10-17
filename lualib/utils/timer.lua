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
end

function timer:start()
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

			last_cb_time = next_cb_time
			next_cb_time = next_cb_time + self._span
			if self._cb then
				pcall(self._cb, last_cb_time)
			end
		end
	end)
end

function timer:stop()
	if not self._stop then
		self._stop = true
		skynet.wakeup(self)
	end
end

return timer
