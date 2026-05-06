---
-- 串口和Socket端口模块
--
-- 本模块提供串口和Socket端口的创建和管理功能
---

local agent_serial = require 'app.port.agent_serial'
local agent_socket = require 'app.port.agent_socket'
local timeout_channel = require 'app.port.timeout_channel'
local helper = require 'app.port.helper'

local _M = {}

---
-- 创建串口
-- @tparam opt 选项数据表
-- @tparam shared_name 共享名称字符串，用于在应用[实例]之间共享此串口
function _M.new_agent_serial(opt, shared_name)
	return agent_serial:new(opt, shared_name)
end

---
-- 创建Socket端口
-- @tparam opt 选项数据表
-- @tparam shared_name 共享名称字符串，用于在应用[实例]之间共享此Socket端口
function _M.new_agent_socket(opt, shared_name)
	return agent_socket:new(opt, shared_name)
end

---
-- 创建串口通道
-- @param conf 配置
-- @param name 名称
function _M.new_serial(conf, name)
	return timeout_channel('serialchannel', conf, name)
end

---
-- 创建Socket通道
-- @param conf 配置
-- @param name 名称
function _M.new_socket(conf, name)
	return timeout_channel('socketchannel', conf, name)
end


_M.helper = helper

return _M
