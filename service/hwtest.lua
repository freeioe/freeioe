local skynet = require 'skynet'
local cjson = require 'cjson.safe'
local hwtest = require 'hwtest'
local log = require 'utils.log'

skynet.start(function()
	local runner = hwtest:new('thingslink', 'x1')
	runner:start()
	while true do
		if runner:finished() then
			break
		end
		skynet.sleep(100)
	end

	log.debug(cjson.encode(runner:result()))
end)
