---
-- Using process-monitor to start/stop 3rd binary process
--

local skynet = require 'skynet'
local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local log = require 'utils.log'

local pm = class("FREEIOE_PROCESS_MONITOR_WRAP")

function pm:initialize(name, cmd, args, options)
	assert(name and cmd)
	self._name = name
	self._cmd = cmd
	local pn = cmd:match("([^/]+)$") or cmd
	self._pid = "/tmp/ioe_pm_"..pn.."_"..self._name..".pid"
	if args then
		self._cmd = cmd .. ' ' .. table.concat(args, ' ')
	end
	self._options = options or {}
end

function pm:get_tmp_path(filename)
	local pn = cmd:match("([^/]+)$") or cmd
	return "/tmp/ioe_pm_"..self._pn.."_"..filename
end

function pm:start()
	if self._started then
		return nil, "Process-monitor already started!"
	end

	local os_id = sysinfo.os_id()
	local arch = sysinfo.cpu_arch()
	assert(os_id, arch)
	local pm_file = './ioe/'..os_id..'/'..arch..'/process-monitor'
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
	log.info('start process-monitor', cmd_str)
	return os.execute(cmd_str)
end

function pm:get_pid()
	local f, err = io.open(self._pid, 'r')
	if not f then
		return nil, 'pid file not found'..err
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
		if self._started then
			log.error("Process-monitor started but pid missing!!!")
		end
		return nil, err
	end
	local r = {os.execute('kill '..pid)}
	skynet.sleep(100)
	self._started = nil
	return table.unpack(r)
end

function pm:status()
	if not self._started then
		return nil, 'Process-monitor is not started'
	end
	local pid, err = self:get_pid()
	if not pid then
		return nil, err
	end
	return os.execute('kill -0 '..pid)
end

--[[
function pm:restart()
	self:stop()
	self:cleanup()
	return self:start()
end
]]--

function pm:cleanup()
	os.execute('rm -f '..self._pid)
	skynet.sleep(100)
end

return pm
