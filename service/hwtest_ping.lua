local skynet = require 'skynet'
local log = require 'utils.log'

local command = {}

local function ping_target(target)
	local r = os.execute('ping -c 1 '..target..' > /dev/null 2>&1')
	if not r then
		log.debug("ping timeout", target)
		return nil , 'Timeout'
	end
	log.debug("ping ok", target)
	return r
end


function command.PING(target, time)
	local time = time or 3

	while time > 0 do
		if ping_target(target) then
			return true
		end
		time = time - 1
		skynet.sleep(100)
	end

	return false, 'Timeout'
end

function command.EXIT()
	skynet.timeout(100, function()
		skynet.exit()
	end)
	return true
end

skynet.start(function()
	--cache.mode('EXIST')
	--
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
end)


