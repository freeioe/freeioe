local skynet = require 'skynet'
local log = require 'utils.logger'.new()

return function(target)
	local ping_service = skynet.newservice('hwtest_ping')

	local r, err = skynet.call(ping_service, 'lua', 'ping', target)
	if r then
		log.debug("PING "..target.." OK")
	else
		log.debug("PING "..target.." FAILED", err)
	end
	skynet.call(ping_service, 'lua', 'exit')

	return r, err
end
