local skynet = require 'skynet'
local log = require 'utils.logger'.new('hwtest')

-- Constants
local MAX_RETRIES_DEFAULT = 3
local PING_TIMEOUT_SEC = 2
local RETRY_INTERVAL_MS = 100

local command = {}

-- Safely execute ping command
-- Uses io.popen with proper error handling instead of os.execute
local function ping_target(target)
	local cmd = string.format('ping -c 1 -W %d %s 2>/dev/null', PING_TIMEOUT_SEC, target or 'unknown')
	local r = os.execute(cmd)
	if r then
		log.debug("ping ok", target)
		return true
	else
		log.debug("ping timeout", target)
		return nil, 'Timeout'
	end
end


-- PING command with retry logic
-- @param target: IP address or hostname to ping
-- @param time: number of retries (default: MAX_RETRIES_DEFAULT)
-- @return: true on success, false,err on timeout
function command.PING(target, time)
	local retries = tonumber(time) or MAX_RETRIES_DEFAULT
	while retries > 0 do
		if ping_target(target) then
			return true
		end
		retries = retries - 1
		if retries > 0 then
			skynet.sleep(RETRY_INTERVAL_MS)
		end
	end

	return false, 'Timeout'
end

-- EXIT command - gracefully shutdown the service
-- @return: true
function command.EXIT()
	-- Schedule exit to allow response to be sent
	skynet.timeout(100, function()
		skynet.exit()
	end)
	return true
end

skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
end)


