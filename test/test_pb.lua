local skynet = require 'skynet'
local pb = require 'buffer.period'

skynet.start(function()
	pb:__test()
end)
