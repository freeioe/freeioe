---
-- Using process-monitor to start/stop 3rd binary process
--

local lfs = require 'lfs'
local skynet = require 'skynet'
local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local log = require 'utils.logger'.new()
local ioe = require 'ioe'

local pm = class("FREEIOE_PROCESS_MONITOR_WRAP")

-- Shell转义函数
local function shell_escape(s)
	if type(s) ~= 'string' then
		s = tostring(s)
	end
	return '"' .. string.gsub(s, '"', '\\"') .. '"'
end

-- 验证进程名称
local function validate_process_name(name)
	if not name or type(name) ~= 'string' then
		return nil, "Invalid process name type"
	end
	-- 只允许字母数字、下划线、短横线、点
	if not string.match(name, '^[%w%.-]+$') then
		return nil, "Invalid process name"
	end
	-- 拒绝路径遍历
	if string.match(name, '%.%.') then
		return nil, "Path traversal not allowed"
	end
	return true
end

function pm:initialize(name, cmd, args, options)
	assert(name and cmd)

	local ok, err = validate_process_name(name)
	if not ok then
		error(err)
	end

	self._name = name
	self._cmd = cmd

	local pn = cmd:match("([^/]+)$") or cmd
	self._pid = "/tmp/ioe_pm_"..pn.."_"..self._name..".pid"

	-- 安全处理args
	if args then
		local escaped_args = {}
		for _, v in ipairs(args) do
			table.insert(escaped_args, shell_escape(v))
		end
		self._cmd = cmd .. ' ' .. table.concat(escaped_args, ' ')
	end

	self._options = options or {}
end

function pm:start()
	if self._started then
		return nil, "Process-monitor already started!"
	end

	local os_kind = sysinfo.os_kind()
	local cpu_arch = sysinfo.cpu_arch()
	assert(os_kind and cpu_arch)

	local pm_file = ioe.dir()..'/'..os_kind..'/'..cpu_arch..'/process-monitor'
	if lfs.attributes(pm_file, "mode") == nil then
		pm_file = 'process-monitor' -- use os bin file
	end

	local cmd = { pm_file, "-z", "-d", "-p", self._pid }

	if self._options.user then
		cmd[#cmd + 1] = "-u"
		cmd[#cmd + 1] = shell_escape(self._options.user)
	end
	cmd[#cmd + 1] = "--"
	cmd[#cmd + 1] = self._cmd

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

	local r = {os.execute('kill '..tostring(pid))}
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

	--- Kill -0 just check whether the pid exists
	return os.execute('kill -0 '..tostring(pid))
end

--[[
function pm:restart()
	self:stop()
	self:cleanup()
	return self:start()
end
]]--

function pm:cleanup()
	os.execute('rm -f '..shell_escape(self._pid))
	skynet.sleep(100)
end

return pm
