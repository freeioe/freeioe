--[[
--  FreeIOE Application utility functions
--]]
--
local ioe = require 'ioe'
local dc = require 'skynet.datacenter'
local _M = {}

--- trim instance name
_M._trim_inst = function(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("", string.byte(c))
	end))
end

-- Valid application instance name
_M.valid_inst = function(s)
	return s and #s > 0 and s == _M._trim_inst(s) and s ~= _M.dev_app_name() and s ~= _M.sys_app_name()
end

-- FreeIOE develop app inst name
_M.dev_app_name = function()
	return '_app'
end

_M.dev_app_path = function()
	return dc.get('DEV_APP_PATH')
end

-- FreeIOE system app inst name
_M.sys_app_name = function()
	return 'ioe'
end

-- Return FreeIOE application local folder path by app's instance name
_M.app_path = function(app_inst)
	if app_inst == _M.dev_app_name() then
		return _M.dev_app_path()
	end
	return ioe.dir(true).."/apps/"..app_inst.."/"
end

return _M
