local sc = require 'socketchannel'
local skynet = require 'skynet'

local function test(channel, req)
	local recv_len = 0
	local resp, err = channel:request(req, function(sock)
		local data, err = sock:read(10)
		if not data then
			return false, err
		end

		recv_len = recv_len + string.len(data)
		print(req, recv_len, string.len(data))
		if recv_len >= 50 then
			-- The data more than 50 will also be returned
			return true, data
		end
		-- Need more data
		return true, data, true
	end, {'eee'})

	if type(resp) == 'table' then
		print('this is a table')
		resp = table.concat(resp)
	end

	print('RECVED', resp, err)

end

skynet.start(function()
	local channel = sc.channel({
		host = "127.0.0.1",
		port = 16000
	})
	channel:connect(true)
	skynet.sleep(50)

	test(channel, 'aaa1')
	skynet.fork(function()
		test(channel, 'aaa')
	end)
	skynet.fork(function()
		test(channel, 'bbb')
	end)
end)
