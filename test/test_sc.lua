local sc = require 'socketchannel'
local skynet = require 'skynet'
local socket = require 'skynet.socket'
local coroutine = require 'skynet.coroutine'

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

function timeout_call(func, ti, ...)
	local channel = select(1, ...)
	print('start timeout_call', os.time())
	local co = coroutine.running()
	local cancel = cancelable_timeout(ti, function()
		skynet.fork(function()
			channel:close()
			--channel:connect(true)
		end)
	end)
	local ret = table.pack(func(...)) 
	cancel() 
	print('end timeout_call', os.time())
	return table.unpack(ret)
end

local function test_return_tables(channel, req)
	local recv_len = 0
	local r, resp, err = pcall(channel.request, channel, req, function(sock)
		local data, err = sock:read(nil)
		if not data then
			return false, err
		end

		recv_len = recv_len + string.len(data)
		print('table_RECV LEN', recv_len, string.len(data))
		if recv_len >= 50 then
			-- The data more than 50 will also be returned
			return true, data
		end
		-- Need more data
		return true, data, true
	end)
	if not r then
		print('ERROR', resp, err)
	end

	if type(resp) == 'table' then
		print('this is a table')
		resp = table.concat(resp)
	end
	print('RECVED', resp, err)
end

local function test_own_buffer(channel, req)
	local buffer = {}
	local header_len = 4
	local r, resp, err = pcall(channel.request, channel, req, function(sock)
		local data, err = sock:read(nil)
		if not data then
			return false, err
		end
		buffer[#buffer + 1] = data

		while true do
			local resp = table.concat(buffer)
			local need_len = header_len
			if string.len(resp) >= header_len then
				need_len = 50 -- string.byte(resp, 4)
			end

			print('buffer_RECV LEN', string.len(resp))
			local recv_len = string.len(resp)
			
			if recv_len > header_len and recv_len == need_len then
				buffer = {}
				return true, resp
			end

			if recv_len > header_len and recv_len > need_len then
				buffer = { string.sub(resp, need_len + 1) }
				return true, string.sub(resp, 1, need_len)
			end

			--- Receive left data
			local data, err = sock:read(need_len - recv_len)
			if not data then
				return false, err
			end
			buffer[#buffer + 1] = data
		end
	end)
	if not r then
		print('ERROR', resp, err)
	else
		print('RECVED', resp, err)
		print('Left in buffer', table.concat(buffer))
	end
end

local function test_read_header(channel, req)
	local buffer = {}
	local r, resp, err = pcall(channel.request, channel, req, function(sock)
		local head, err = sock:read(4)
		if not head then
			return false, err
		end

		local need_len = 50 -- string.byte(head, 3)

		--- Receive left data
		local data, err = sock:read(need_len - 4)
		if not data then
			return false, err
		end
		--print('Left in socket buffer', sock:read(nil))
		return true, head..data
	end)
	if not r then
		print("ERROR", resp, err)
	else
		print('RECVED', resp, err)
	end
end

skynet.start(function()
	local channel = sc.channel({
		host = "127.0.0.1",
		port = 16000
	})
	channel:connect(true)
	skynet.sleep(50)

	print('before return table')
	--test_return_tables(channel, 'return table\n')
	timeout_call(test_return_tables, 500, channel, 'return table\n')

	print('before own buffer')
	--test_return_tables(channel, 'bbb')
	timeout_call(test_own_buffer, 1000, channel, 'own buffer\n')
	print('before read header')
	timeout_call(test_read_header, 1000, channel, 'read header\n')
end)
