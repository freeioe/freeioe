local skynet = require 'skynet'
local log = require 'utils.logger'.new('hwtest')

-- Constants
local MAX_RETRIES_DEFAULT = 3
local PING_TIMEOUT_SEC = 1
local RETRY_INTERVAL_MS = 100

local command = {}

-- Validate IP address or hostname format
-- Returns true if valid, false otherwise
local function validate_target(target)
	if not target or type(target) ~= 'string' or target == '' then
		return false
	end

	-- Remove leading/trailing whitespace
	target = target:match('^%s*(.-)%s*$')

	-- Check length (prevent DoS with extremely long hostnames)
	if #target > 253 then
		return false
	end

	-- Basic hostname validation: letters, digits, hyphens, dots only
	-- Prevents command injection through shell metacharacters
	if not target:match('^[a-zA-Z0-9%.%-]+$') then
		return false
	end

	-- Prevent consecutive dots or starting/ending with dot/hyphen
	if target:match('%.%.') or target:match('^%.') or target:match('%.$') then
		return false
	end
	if target:match('%-') or target:match('%-$') then
		return false
	end

	return true
end

-- Safely execute ping command
-- Uses io.popen with proper error handling instead of os.execute
local function ping_target(target)
	if not validate_target(target) then
		log.error("Invalid ping target:", target)
		return nil, 'Invalid target'
	end

	local cmd = string.format('ping -c 1 -W %d %s 2>/dev/null', PING_TIMEOUT_SEC, target)
	local pipe = io.popen(cmd)

	if not pipe then
		log.error("Failed to execute ping for target:", target)
		return nil, 'Ping execution failed'
	end

	local result = pipe:read('*a')
	local success = pipe:close()

	-- ping returns 0 on success, non-zero on failure
	if success then
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
	if not target then
		return false, 'Target is required'
	end

	local retries = tonumber(time) or MAX_RETRIES_DEFAULT
	local current_retry = 0

	while current_retry < retries do
		if ping_target(target) then
			return true
		end
		current_retry = current_retry + 1
		if current_retry < retries then
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


