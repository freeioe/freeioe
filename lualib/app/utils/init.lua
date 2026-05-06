---
-- 应用工具函数模块
--
-- 本模块为FreeIOE应用提供工具函数，
-- 包括实例名称验证和路径解析。
---

local ioe = require 'ioe'
local dc = require 'skynet.datacenter'
local _M = {}

---
-- 将实例名称修剪为有效字符
-- 移除除下划线外的所有非字母数字字符
-- @param s: 实例名称字符串
-- @return: 清理后的实例名称
---
_M._trim_inst = function(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("", string.byte(c))
	end))
end

---
-- 验证应用实例名称
-- 检查名称是否非空、仅包含有效字符、
-- 且不是保留的系统名称
-- @param s: 要验证的实例名称
-- @return: 有效返回true，否则返回false
---
_M.valid_inst = function(s)
	return s and #s > 0 and s == _M._trim_inst(s) and s ~= _M.dev_app_name() and s ~= _M.sys_app_name()
end

---
-- 获取FreeIOE开发应用实例名称
-- @return: 开发应用名称'_app'
---
_M.dev_app_name = function()
	return '_app'
end

---
-- 获取FreeIOE开发应用路径
-- @return: 开发应用目录路径
---
_M.dev_app_path = function()
	return dc.get('DEV_APP_PATH')
end

---
-- 获取FreeIOE系统应用实例名称
-- @return: 系统应用名称'ioe'
---
_M.sys_app_name = function()
	return 'ioe'
end

---
-- 根据实例名称获取应用本地文件夹路径
-- @param app_inst: 应用实例名称
-- @return: 应用的本地文件夹路径
---
_M.app_path = function(app_inst)
	if app_inst == _M.dev_app_name() then
		return _M.dev_app_path()
	end
	return ioe.dir(true).."/apps/"..app_inst.."/"
end

return _M
