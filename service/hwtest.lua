local skynet = require 'skynet'
local cjson = require 'cjson.safe'
local hwtest = require 'hwtest'
local log = require 'utils.logger'.new('hwtest')

skynet.start(function()
	local runner = hwtest:new('thingslink', 'x1')
	runner:start()

	skynet.timeout(10000, function()
		while true do
			skynet.sleep(500)
			log.notice(cjson.encode(runner:result()))
		end
	end)

	while true do
		if runner:finished() then
			break
		end
		skynet.sleep(100)
	end

	log.warning("Hardware Test Finished!!!")
	os.execute([[echo "Hardware Test Finished!!!" > /dev/kmsg]])

	local result, err = cjson.encode(runner:result())
	if not result then
		log.error("Failed to encode hwtest result:", err)
		os.execute([[echo "Failed to encode hwtest result:]]..tostring(err)..[[" > /dev/kmsg]])
		return
	else
		log.notice(result)

		local f, err = io.open('/tmp/hwtest.result', 'w+')
		if f then
			f:write(result)
			f:close()
			log.info("Hardware test result saved to /tmp/hwtest.result")
		else
			log.error("Failed to write hwtest result file:", err)
		end
	end
	-- Do not quit this service
	-- skynet.exit()
end)
