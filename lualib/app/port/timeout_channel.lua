---
-- 超时通道模块
--
-- 本模块提供带超时功能的串口和Socket通道
---

local skynet = require "skynet"
local class = require 'middleclass'
local uuid = require 'uuid'
local log = require 'utils.loggger'.new()

---
-- 应用端口类
--
-- 封装串口和Socket通道，提供超时和重连功能
---
local app_port = class('FREEIOE_APP_SERIAL_PORT_CLASS')

---
-- 端口请求处理函数
-- @param chn 通道对象
-- @param request 请求数据
-- @param response 响应处理函数
-- @param padding 填充数据
-- @return 响应数据或错误信息
local function port_request(chn, request, response, padding)
	local r, data, err = skynet.pcall(chn.request, chn, request, function(sock)
		local r, data, info = skynet.pcall(response, sock)
		if not r then
			--log.trace(data)
			return false, data
		end
		return data, info
	end, padding)

	if not r then
		--log.trace(data)
		return false, data
	end
	return data, err
end

--- 超时错误对象 */
local timeout_error = setmetatable({}, {__tostring = function() return "[Error: channel timeout]" end })

---
-- 超时调用函数
-- @param ti 超时时间
-- @param f 要执行的函数
-- @param ... 函数参数
-- @return 函数执行结果或超时错误
local function timeout_call(ti, f, ...)
	local token = {}
	local ret

	skynet.fork(function(...)
		ret = table.pack(pcall(f, ...))
		skynet.wakeup(token)
	end, ...)

	skynet.sleep(ti, token)
	if ret then
		if ret[1] then
			return table.unpack(ret, 2)
		else
			error(ret[2])
		end
	else
		-- 超时
		--log.trace('timeout error')
		return false, timeout_error
	end
end

---
-- 初始化端口对象
-- @param port_type 端口类型（如'serialchannel'、'socketchannel'）
-- @param conf 端口配置
-- @param share_name 共享名称
function app_port:initialize(port_type, conf, share_name)
	local r, m = pcall(require, port_type)
	assert(r, m)
	assert(conf, "Serial port configuration missing")

	self._name = share_name or uuid()
	self._conf = conf
	self._port_m = m
	self._chn = m.channel(conf)
end

---
-- 获取端口名称
-- @return 端口名称
function app_port:get_name()
	return self._name
end

---
-- 获取端口配置
-- @return 配置表
function app_port:get_conf()
	return self._conf
end

---
-- 连接端口
-- @param only_once 是否只连接一次
-- @param timeout 超时时间（毫秒）
-- @return 连接结果
function app_port:connect(only_once, timeout)
	if timeout then
		return self:timeout_call(timeout, self._chn.connect, self._chn, only_once)
	else
		return self._chn:connect(only_once)
	end
end

---
-- 超时调用函数
-- @param timeout 超时时间
-- @param func 要调用的函数
-- @param ... 函数参数
-- @return 调用结果或错误
function app_port:timeout_call(timeout, func, ...)
	local r, err = timeout_call(timeout, func, ...)
	--[[
	if not r and err == timeout_error then
		log.error('Port timeout then reopen it')
		self:reopen()
	end
	]]--
	return r, err
end

---
-- 发送请求并等待响应
-- @param request 请求数据
-- @param response 响应处理函数
-- @param padding 填充数据
-- @param timeout 超时时间（毫秒）
-- @return 响应数据或错误
function app_port:request(request, response, padding, timeout)
	if timeout then
		return self:timeout_call(timeout / 10, port_request, self._chn, request, response, padding)
	else
		return port_request(self._chn, request, response, padding)
	end
end

---
-- 重新打开端口
-- @param conf 新的配置（可选，默认使用原配置）
function app_port:reopen(conf)
	if self._chn then
		self._chn:close()
	end
	self._chn = self._port_m.channel(conf or self._conf)
end

---
-- 关闭端口
function app_port:close()
	if self._chn then
		self._chn:close()
		self._chn = nil
	end
end

return app_port
