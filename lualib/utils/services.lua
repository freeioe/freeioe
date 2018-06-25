---
-- Services Control Utils 
--
local lfs = require 'lfs'
local skynet = require 'skynet'
local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local pm = require 'utils.process_monitor'

local services = class("FREEIOE_SERVICES_CONTRL_API")

function services:initialize(name, cmd, args, options)
	assert(name and cmd)
	self._name = "ioe_"..name
	self._cmd = cmd
	if args then
		self._cmd = cmd .. ' ' .. table.concat(args, ' ')
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
	return os.execute(self._file.." "..action)
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
	os.execute("chmod a+x "..self._file)
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
	os.execute('rm -f '..self._file)
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
	return os.execute('kill -0 '..pid)
end

return services
