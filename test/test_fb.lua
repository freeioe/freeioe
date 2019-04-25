local skynet = require 'skynet'
local fb = require 'buffer.file'

skynet.start(function()
	fb:__test()
end)
