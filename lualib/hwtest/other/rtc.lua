local skynet = require 'skynet'
local log = require 'utils.log'

local exec = function(cmd, inplace)
	local cmd = cmd..' 2>/dev/null'
	local f, err = io.popen(cmd)
	if not f then
		return nil, err
	end
	local s = f:read('*a')
	f:close()
	return s
end


return function (rtc_file)
	exec('hwclock -w')
	skynet.sleep(300)
	local rtc_test = 'hwclock -r'
	if rtc_file then
		rtc_test = rtc_test .. ' -f ' .. rtc_file
	end

	local date = os.date()
	local rtc_date = exec(rtc_test)
	if not rtc_date then
		return false
	end

	log.debug(date, rtc_date)

	return string.sub(date, 1, 17) == string.sub(rtc_date, 1, 17)
end
