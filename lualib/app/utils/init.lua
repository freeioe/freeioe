---
-- Application Utility Functions Module
--
-- This module provides utility functions for FreeIOE applications,
-- including instance name validation and path resolution.
---

local ioe = require 'ioe'
local dc = require 'skynet.datacenter'
local _M = {}

---
-- Trim instance name to valid characters
-- Removes all non-alphanumeric characters except underscores
-- @param s: instance name string
-- @return: sanitized instance name
---
_M._trim_inst = function(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("", string.byte(c))
	end))
end

---
-- Validate application instance name
-- Checks if name is non-empty, contains only valid characters,
-- and is not a reserved system name
-- @param s: instance name to validate
-- @return: true if valid, false otherwise
---
_M.valid_inst = function(s)
	return s and #s > 0 and s == _M._trim_inst(s) and s ~= _M.dev_app_name() and s ~= _M.sys_app_name()
end

---
-- Get FreeIOE development application instance name
-- @return: development app name '_app'
---
_M.dev_app_name = function()
	return '_app'
end

---
-- Get FreeIOE development application path
-- @return: development app directory path
---
_M.dev_app_path = function()
	return dc.get('DEV_APP_PATH')
end

---
-- Get FreeIOE system application instance name
-- @return: system app name 'ioe'
---
_M.sys_app_name = function()
	return 'ioe'
end

---
-- Get application local folder path by instance name
-- @param app_inst: application instance name
-- @return: local folder path for the application
---
_M.app_path = function(app_inst)
	if app_inst == _M.dev_app_name() then
		return _M.dev_app_path()
	end
	return ioe.dir(true).."/apps/"..app_inst.."/"
end

return _M
