local skynet = require 'skynet'
local socket = require 'skynet.socket'

function cancelable_timeout(ti, func)
	local function cb()
		if func then
			func()
		end
	end
	local function cancel()
		func = nil
	end
	skynet.timeout(ti, cb)
	return cancel
end

function timeout_call(func, ti, tofunc, ...)
	print('start timeout_call', os.time())
	local cancel = cancelable_timeout(ti, tofunc)
	local ret = table.pack(func(...)) 
	cancel() 
	print('end timeout_call', os.time())
	return table.unpack(ret)
end

local function test_own_buffer(sock, req, timeout)
	local buffer = {}
	local header_len = 4

	local r, err = socket.write(sock, req)
	if not r then
		return false, "Failed to send"
	end

	local sock_ok = true
	local need_len = header_len
	while sock_ok do
		print('before block')
		socket.block(sock)
		print('after block')

		local data, err = socket.read(sock, nil)
		if not data then
			buffer[#buffer + 1] = err
			sock_ok = false
		else
			buffer[#buffer + 1] = data
		end

		local resp = table.concat(buffer)
		if string.len(resp) >= header_len then
			need_len = 50 -- string.byte(resp, 4)
		end

		print('RECV LEN', string.len(resp))
		local recv_len = string.len(resp)

		if recv_len > header_len then
			if recv_len == need_len then
				buffer = {}
				return true, resp, sock_ok
			end

			if recv_len > need_len then
				buffer = { string.sub(resp, need_len + 1) }
				print('Left in buffer', table.concat(buffer))
				return true, string.sub(resp, 1, need_len), sock_ok
			end
		end
	end

	return false, "Socket closed"
end

local function test_read_header(sock, req)
	local buffer = {}
	local sock_ok = true

	local r, err = socket.write(sock, req)
	if not r then
		return false, "Failed to send"
	end

	print('before block 1')
	socket.block(sock)
	print('after block 1')
	local head, err = socket.read(sock, 4)
	if not head then
		return false, "Socket closed"
	end

	local need_len = 50 -- string.byte(head, 3)

	--- Receive left data
	print('before block 2')
	socket.block(sock)
	print('after block 2')
	local data, err = socket.read(sock, need_len - 4)
	if not data then
		if string.len(err) < (need_len - 4) then
			return false, err
		end
		sock_ok = false
	end
	return true, head..data, sock_ok
end

skynet.start(function()
	local host = '127.0.0.1'
	local port = 16000
	local sock, err = socket.open(host, port)
	if not sock then
		print('Failed to connect', err)
	end
	skynet.sleep(50)

	--local r, data, sock_ok = test_own_buffer(sock, 'own buffer\n')
	local r, data, sock_ok = timeout_call(test_own_buffer, 500, function() socket.close(sock) end, sock, 'own buffer\n')

	print(r, data, sock_ok)
	if not r or not sock_ok then
		sock = socket.open(host, port)
		if not sock then
			print('Failed to connect', err)
		end
		skynet.sleep(50)
	end
	--local r, data, sock_ok = test_read_header(sock, 'read header\n')
	local r, data, sock_ok = timeout_call(test_read_header, 1000, function() socket.close(sock) end, sock, 'read header\n')
	print(r, data, sock_ok)
end)
