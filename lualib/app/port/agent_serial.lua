---
-- 串口代理模块
--
-- 本模块提供串口通道的代理服务
-- 支持请求/响应模式和超时控制
---

local skynet = require "skynet"
local service = require "skynet.service"
local class = require 'middleclass'
local uuid = require 'uuid'

---
-- 应用串口类
--
-- 封装串口通道代理服务
---
local app_port = class('FREEIOE_APP_SERIAL_PORT_CLASS')

---
-- 代理服务函数
-- @param ... 服务参数（应用名称、配置）
local function agent_service(...)
	local skynet = require "skynet"
	local serialchannel = require "serialchannel"
	local logger = require 'app.logger'

	--skynet.error(...)	-- (...) passed from service.new
	local args = table.pack(...)
	local name = assert(args[1])
	local conf = args[2] or {}

	local log = logger:new(name)

	local command = {}
	local chn = serialchannel.channel(conf)

	function command.request(request, response, padding, ...)
		local resp, err = assert(load(response))
		if not resp then
			return false, 'Response function code loading failed'
		end

		local r, data, err = skynet.pcall(function(...)
			return chn:request(request, function(sock, ...)
				local r, data, info = skynet.pcall(resp, sock)
				if not r then
					log:trace(data)
					return false, data
				end
				return data, info
			end, padding)
		end, ...)
		if not r then
			log:trace(data)
			return false, data
		end
		return data, err
	end

	function command.connect(only_once)
		return chn:connect(only_once)
	end

	function command.reopen(new_conf)
		log:trace('reopen socket channel')
		conf = new_conf or conf
		chn:close()
		chn = serialchannel.channel(conf)
	end

	function command.close()
		return chn:close()
	end

	skynet.start(function()
		skynet.dispatch("lua", function(session, address, cmd, ...)
			skynet.ret(skynet.pack(command[cmd](...)))
		end)
	end)
end

---
-- 检查函数是否只有一个upvalue
-- @param func 要检查的函数
local function check(func)
	local info = debug.getinfo(func, "u")
	assert(info.nups == 1)
	assert(debug.getupvalue(func,1) == "_ENV")
end

--- 超时错误对象 */
local timeout_error = setmetatable({}, {__tostring = function() return "[Error: serial timeout]" end })

---
-- 超时调用函数
-- @param ti 超时时间
-- @param ... 要调用的函数和参数
-- @return 函数执行结果或超时错误
local function timeout_call(ti, ...)
	local token = {}
	local ret

	skynet.fork(function(...)
		ret = table.pack(pcall(skynet.call, ...))
		skynet.wakeup(token)
	end, ...)

	skynet.sleep(ti, token)
	if ret then
		if ret[1] then
			return table.unpack(ret, 2, ret.n)
		else
			error(ret[2])
		end
	else
		-- 超时
		return false, timeout_error
	end
end

---
-- 初始化串口对象
-- @param conf 串口配置
-- @param share_name 共享名称
function app_port:initialize(conf, share_name)
	assert(conf, "Serial port configuration missing")
	self._name = share_name or uuid()
	self._app_name = G_APP_NAME
	self._conf = conf
	self._agent = service.new("APP.SERIAL_PORT."..self._name, agent_service, self._app_name, self._conf)
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
		return self:timeout_call(timeout, "connect", only_once)
	else
		return skynet.call(self._agent, "lua", "connect", only_once)
	end
end

---
-- 超时调用函数
-- @param timeout 超时时间
-- @param func 要调用的函数
-- @param ... 函数参数
-- @return 调用结果或错误
function app_port:timeout_call(timeout, func, ...)
	local r, err = timeout_call(timeout, self._agent, "lua", func, ...)
	if not r and err == timeout_error then
		self:reopen()
	end
	return r, err
end

---
-- 发送请求并等待响应
-- @param request 请求数据
-- @param response 响应处理函数
-- @param padding 填充数据
-- @param timeout 超时时间（毫秒）
-- @param ... 额外参数
-- @return 响应数据或错误
function app_port:request(request, response, padding, timeout, ...)
	check(response)
	local code = string.dump(response)
	if timeout then
		return self:timeout_call(timeout / 10, "request", request, code, padding, ...)
	else
		return skynet.call(self._agent, "lua", "request", request, code, padding, ...)
	end
end

---
-- 重新打开端口
-- @param conf 新的配置（可选）
-- @return 操作结果
function app_port:reopen(conf)
	return skynet.call(self._agent, "lua", "reopen", conf)
end

---
-- 关闭端口
-- @return 操作结果
function app_port:close()
	return skynet.call(self._agent, "lua", "close", conf)
end

return app_port
