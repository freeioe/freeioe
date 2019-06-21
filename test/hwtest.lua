local skynet = require 'skynet'
local socket = require 'skynet.socket'


skynet.start(function()
	local host = '127.0.0.1'
	local port = 16000
	local sock, err = socket.open(host, port)
end)
