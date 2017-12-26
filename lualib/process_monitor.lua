---
-- Using process-monitor to start/stop 3rd binary process
--

local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local log = require 'utils.log'

local pm = class("IOT_PROCESS_MONITOR_WRAP")

function pm:initialize(name, cmd, args, options)
	assert(name and cmd)
	self._name = name
	self._cmd = cmd
	local pn = cmd:match("([^/]+)$") or cmd
	self._pid = "/tmp/iot_pm_"..self._name.."_"..pn..".pid"
	if args then
		self._cmd = cmd .. ' ' .. table.concat(args, ' ')
	end
	self._options = options or {}
end

function pm:start()
	self:stop()

	local plat = sysinfo.platform()
	assert(plat)
	local pm_file = 'process-monitor'
	if plat == 'openwrt' then
		pm_file = './iot/openwrt/arm_cortex-a9_neon/process-monitor'
	end
	if plat == 'mx0' then
		pm_file = './iot/linux/mx0/process-monitor'
	end
	if plat == 'mips_24kc' then
		pm_file = './iot/openwrt/mips_24kc/process-monitor'
	end
	if plat == 'amd64' then
		pm_file = './iot/linux/x86_64/process-monitor'
	end

	local cmd = { pm_file, "-z", "-d", "-p", self._pid }
	--local cmd = { pm_file, "-p", self._pid }
	if self._options.user then
		cmd[#cmd + 1] = "-u"
		cmd[#cmd + 1] = self._options.user
	end
	cmd[#cmd + 1] = "--"
	cmd[#cmd + 1] = self._cmd
	--cmd[#cmd + 1] = "> /dev/null &"

	local cmd_str = table.concat(cmd, ' ') 
	log.debug('process-monitor', cmd_str)
	return os.execute(cmd_str)
end

function pm:get_pid()
	local f, err = io.open(self._pid, 'r')
	if not f then
		return nil, 'pid file not found'
	end
	local id = f:read('*a')
	f:close()
	local pid = tonumber(id)
	if not pid then
		return nil, "pid file read error"
	end
	return pid
end

function pm:stop()
	local pid, err = self:get_pid()
	if not pid then
		return nil, err
	end
	return os.execute('kill '..pid)
end

function pm:status()
	local pid, err = self:get_pid()
	if not pid then
		return nil, err
	end
	return os.execute('kill -0 '..pid)
end

function pm:restart()
	self:stop()
	skynet.sleep(100)
	return self:start()
end

return pm
