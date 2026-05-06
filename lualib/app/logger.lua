--- 应用日志记录器模块
-- @module app.logger
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 提供带压缩功能的应用日志记录器

local class = require 'middleclass'
local log = require 'utils.log'
local formatter = require 'log.formatter.concat'.new('\t')

local logger = class("APP_MGR_LOG")

--- 初始化日志记录器
-- @param name 日志记录器名称
-- @param logger_m 可选的外部日志模块
function logger:initialize(name, logger_m)
	assert(name)
	self._name = name
	self._log = logger_m or log
	self._log_buf = {}
end

--- 记录日志
-- @param level 日志级别
-- @param info 日志信息
-- @param ... 额外参数
function logger:log(level, info, ...)
	--lvl = log.lvl2number(level)

	local info = self._name and '::'..self._name..':: '..info or info
	local s = formatter(info, ...)
	local now = os.time()
	local los = self._log_buf[level]
	if los then
		if los.s == s and (now - los.t) < 60 then
			los.t = now
			los.c = los.c + 1
			if (now - los.ts) >= (60 * 10) then
				local f = assert(self._log[level])
				f(string.format('[%d ZIPED %d-%d]', los.c, los.ts, now), s)
				los.c = 0
				los.ts = now
			end
			return
		else
			if los.c > 0 then
				local f = assert(self._log[level])
				f(string.format('[%d ZIPED %d-%d ]', los.c, los.ts, los.t), s)
			end
		end
	end

	self._log_buf[level] = {
		ts = now,
		t = now,
		s = s,
		c = 0,
	}
	local f = assert(self._log[level])
	return f(...)
end

--- 带名称记录日志
-- @param level 日志级别
-- @param info 日志信息
-- @param ... 额外参数
function logger:log_with_name(level, info, ...)
	assert(level)
	assert(info)
	local info = self._name and '::'..self._name..':: '..info or info
	--lvl = log.lvl2number(level)
	local f = assert(self._log[level])
	return f(info, ...)
end

--- 创建日志级别函数
-- @param logger 日志记录器对象
-- @param name 函数名称
local function make_func(logger, name)
	logger[name] = function(self, ...)
		return self:log_with_name(name, ...)
	end
end

--- 创建各个日志级别函数
make_func(logger, 'trace')    -- 追踪级别
make_func(logger, 'debug')    -- 调试级别
make_func(logger, 'info')     -- 信息级别
make_func(logger, 'notice')   -- 通知级别
make_func(logger, 'warning')  -- 警告级别
make_func(logger, 'error')    -- 错误级别
make_func(logger, 'fatal')    -- 致命级别

return logger
