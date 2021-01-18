local skynet = require 'skynet'
local class = require 'middleclass'

local recv = class('mqtt.skynet.receiver')

function recv:initialize(read_func, timeout)
	self._read_func = read_func
	self._timeout = timeout or 100
	self._buf = {}
	self:_start()
end

function recv:set_timeout(timeout)
	self._timeout = timeout * 100
end

function recv:shutdown(shutdown)
	assert(shutdown)
	return function()
		shutdown()
		self:_stop()
	end
end

function recv:_start()
	if self._started then
		return true
	end
	self._started = true

	skynet.fork(function()
		self:work_proc()
	end)
	return true
end

function recv:work_proc()
	while not self._close do
		local r, data, err = pcall(self._read_func)
		if not r or not data then
			self._socket_closed = true
			break
		end
		table.insert(self._buf, data)
		if self._buf_wait then
			skynet.wakeup(self._buf_wait)
		end
	end
	self._started = false
	if self._close then
		skynet.wakeup(self._close)
	end
end

function recv:__call(size)
	if self._socket_closed then
		return false, "closed"
	end

	local read_size = function(size)
		local buf = table.concat(self._buf)
		self._buf = {}
		if string.len(buf) >= size then
			if string.len(buf) == size then
				return buf
			else
				self._buf[1] = string.sub(buf, size + 1)
				return string.sub(buf, 1, size)
			end
		else
			self._buf[1] = buf
			return 
		end
	end

	local sleep_wait = function()
		self._buf_wait = {}
		skynet.sleep(self._timeout or 100, self._buf_wait)
		self._buf_wait = nil
	end

	local now = skynet.now()
	while not self._timeout or skynet.now() - now < self._timeout do
		if #self._buf == 0 then
			sleep_wait()
		end
		local data = read_size(size)
		if not data then
			sleep_wait()
		else
			return data
		end
	end
	return false, "timeout"
end

function recv:_stop()
	if not self._started then
		return
	end
	self._close = {}
	skynet.wait(self._close)
	self._close = nil
end

return recv
