local skynet = require 'skynet'
local ubus = require 'ubus'
local cjson = require 'cjson.safe'

skynet.start(function()
	local con = ubus:new()
	print('connect result', con:connect("172.30.11.230", 11000))

	print('connect status', con:status())

	print('objects', cjson.encode(con:objects()))

	print('call', cjson.encode(con:call('system', 'info')))
	print('call', cjson.encode(con:call('network.interface.lan', 'status')))
end)
