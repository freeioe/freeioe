---
-- Services Control Utils
--
local lfs = require 'lfs'
local skynet = require 'skynet'
local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local pm = require 'utils.process_monitor'

local services = class("FREEIOE_SERVICES_CONTRL_API")

-- Shell转义函数
local function shell_escape(s)
	if type(s) ~= 'string' then
		s = tostring(s)
	end
	return '"' .. string.gsub(s, '"', '\\"') .. '"'
end

-- 验证服务名称
local function validate_service_name(name)
	if not name or type(name) ~= 'string' then
		return nil, "Invalid service name type"
	end
	-- 只允许字母数字、下划线、短横线
	if not string.match(name, '^[%w_-]+$') then
		return nil, "Invalid service name"
	end
	-- 拒绝路径遍历
	if string.match(name, '%.%.') then
		return nil, "Path traversal not allowed"
	end
	return true
end

function services:initialize(name, cmd, args, options)
	assert(name and cmd)

	local ok, err = validate_service_name(name)
	if not ok then
		error(err)
	end

	self._name = "ioe_"..name
	self._cmd = cmd

	-- 安全处理args
	if args then
		local escaped_args = {}
		for _, v in ipairs(args) do
			table.insert(escaped_args, shell_escape(v))
		end
		self._cmd = cmd .. ' ' .. table.concat(escaped_args, ' ')
	end

	self._pid = "/tmp/service_"..self._name..".pid"
	self._file = "/etc/init.d/"..self._name
	--self._file = "/tmp/"..self._name

	local os_id = sysinfo.os_id()
	if string.lower(os_id) ~= 'openwrt' then
		self._pm = pm:new(name, cmd, args, options)
	end
	self._options = options or {}
end

local procd_file = [[
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service () {
	procd_open_instance
	procd_set_param command %s
	procd_set_param pidfile %s
	procd_set_param respawn
	procd_close_instance
}
]]

function services:_ctrl(action)
	local cmd = shell_escape(self._file).." "..action
	return os.execute(cmd)
end

function services:create(check_exits)
	if self._pm then
		return true
	end
	local s = string.format(procd_file, self._cmd, self._pid)

	if lfs.attributes(self._file, "mode") == 'file' then
		if check_exits then
			return nil, "Service already exits!"
		else
			self:_ctrl('stop')
			self:_ctrl('disable')
		end
	end

	local f, err = io.open(self._file, "w+")
	if not f then
		return nil, err
	end

	f:write(s)
	f:close()
	os.execute("chmod a+x "..shell_escape(self._file))
	--return self:_ctrl("enable")
	return true
end

function services:cleanup()
	if self._pm then
		return self._pm:cleanup()
	end
end

function services:remove()
	if self._pm then
		return true
	end

	self:_ctrl("disable")
	os.execute('rm -f '..shell_escape(self._file))
end

function services:__gc()
	if self._pm then
		return self._pm:stop()
	end

	self:stop()
	self:remove()
end

function services:start()
	if self._pm then
		return self._pm:start()
	end

	return self:_ctrl("start")
end

function services:stop()
	if self._pm then
		return self._pm:stop()
	end

	return self:_ctrl("stop")
end

function services:reload()
	if self._pm then
		return nil, "Not support"
	end

	return self:_ctrl("reload")
end

function services:restart()
	if self._pm then
		return nil, "Not support"
	end

	return self:_ctrl("restart")
end

function services:get_pid()
	if self._pm then
		return self._pm:get_pid()
	end

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

function services:status()
	if self._pm then
		return self._pm:status()
	end

	local pid, err = self:get_pid()
	if not pid then
		return nil, err
	end

	--- Kill -0 just check whether the pid exists
	return os.execute('kill -0 '..tostring(pid))
end

return services
