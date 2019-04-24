local skynet = require 'skynet'
local fb = require 'utils.fb'

skynet.start(function()
	fb:test()
end)
