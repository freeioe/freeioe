local skynet = require 'skynet'
local class = require 'middleclass'

local recv = class('mqtt.skynet.receiver')

recv.static.map_funcs = function(read_func, shutdown, timeout)
	assert(read_func, 'Read function missing')
	assert(shutdown, 'Shutdown function missing')
	local obj = recv:new(read_func, shutdown, timeout)
	return obj, obj:shutdown()
end

function recv:initialize(read_func, shutdown, timeout)
	self._read_func = read_func
	self._shutdown = shutdown
	self._timeout = timeout or 100
	self._buf = {}
	self._started = nil
	self._start_time = nil
	self:_start()
end

function recv:set_timeout(timeout)
	self._timeout = timeout * 100
end

function recv:shutdown()
	return function()
		-- only call shutdown if started
		if self._started then
			self._closing = true
			self._shutdown()
		end
	end
end

function recv:_start()
	assert(not self._started)
	-- Set the started flag
	self._started = {}

	--- Fork the work_proc
	skynet.fork(function()
		self:work_proc()
	end)

	--- Wait for started
	skynet.sleep(100, self._started)
	assert(self._start_time)
	return true
end

function recv:work_proc()
	--- Set the start_time
	self._start_time = skynet.now()
	--- Wakeup the _start's sleep
	skynet.wakeup(self._started)

	--- Work loop
	while not self._closing do
		--- Read util any byte ready
		local r, data, err = pcall(self._read_func)
		if not r or not data then
			break
		end
		--- Insert to buffer
		table.insert(self._buf, data)
		if self._buf_wait then
			--- Wake up buf wait if any
			skynet.wakeup(self._buf_wait)
		end
	end

	-- Cleanup
	self._start_time = nil
	self._started = nil
	--- Wake up buf wait if any
	if self._buf_wait then
		skynet.wakeup(self._buf_wait)
	end
	-- shutdown the socket if not in closing
	if not self._closing then
		self._shutdown()
	else
		self._closing = nil
	end
end

function recv:__call(size)
	--- Check for socket close
	if not self._started or self._closing then
		return false, "closed"
	end

	--- Read buffer data and pop specified size
	local read_size = function(size)
		assert(size)
		if #self._buf == 0 then
			return
		end

		--- concat buffer
		local buf = table.concat(self._buf)
		self._buf = {}
		--- check size
		if string.len(buf) >= size then
			if string.len(buf) == size then
				return buf
			else
				self._buf[1] = string.sub(buf, size + 1)
				return string.sub(buf, 1, size)
			end
		else
			--- set back buffer
			self._buf[1] = buf
			return 
		end
	end

	local now = skynet.now()
	--- Check timeout
	while not self._timeout or skynet.now() - now < self._timeout do
		--- Try read
		local data = read_size(size)
		if data then
			return data
		end

		--- Sleep and wait for buffer
		self._buf_wait = {}
		skynet.sleep(self._timeout or 100, self._buf_wait)
		self._buf_wait = nil

		-- Check for socket closing
		if not self._started or self._closing then
			return false, "closed"
		end
	end
	return false, "timeout"
end

return recv
