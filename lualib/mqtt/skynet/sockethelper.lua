local socket = require "skynet.socket"
local skynet = require "skynet"

local readbytes = socket.read
local writebytes = socket.write

local sockethelper = {}
local socket_error = setmetatable({} , { __tostring = function() return "[Socket Error]" end })

sockethelper.socket_error = socket_error

function sockethelper.readfunc(fd)
	return function (sz)
		return readbytes(fd, sz)
	end
end

sockethelper.readall = socket.readall

function sockethelper.writefunc(fd)
	return function(content)
		return writebytes(fd, content)
	end
end

function sockethelper.connect(host, port, timeout)
	local fd
	if timeout then
		local drop_fd
		local co = coroutine.running()
		-- asynchronous connect
		skynet.fork(function()
			fd = socket.open(host, port)
			if drop_fd then
				-- sockethelper.connect already return, and raise socket_error
				socket.close(fd)
			else
				-- socket.open before sleep, wakeup.
				skynet.wakeup(co)
			end
		end)
		skynet.sleep(timeout)
		if not fd then
			-- not connect yet
			drop_fd = true
		end
	else
		-- block connect
		fd = socket.open(host, port)
	end
	if fd then
		return fd
	end
	error(socket_error)
end

function sockethelper.close(fd)
	socket.close(fd)
end

function sockethelper.shutdown(fd)
	socket.shutdown(fd)
end

return sockethelper
