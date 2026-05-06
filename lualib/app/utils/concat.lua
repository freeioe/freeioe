---
-- 值连接模块
--
-- 本模块提供延迟值收集和计算触发功能。
-- 用于在处理之前从多个源收集值。
---

local class = require 'middleclass'
local ioe = require 'ioe'
local skynet = require 'skynet'
local cancelable_timeout = require 'cancelable_timeout'

---
-- 连接类
--
-- 从多个源收集值并在可选延迟后触发计算。
---
local concat = class('APP_UTILS_CONCAT')

---
-- 初始化连接实例
-- @param func: 用收集的值调用的计算函数
-- @param need_all: 如果为true，在计算前等待所有源
-- @param delay: 计算前的可选延迟（毫秒）
-- @param timeout: 值过期的可选超时（毫秒）
---
function concat:initialize(func, need_all, delay, timeout)
	assert(func, "Calculate function missing")

	self._calc = func
	self._need_all = need_all
	self._delay = delay
	self._timeout = timeout

	self._source = {}
end

---
-- 添加要收集的值源
-- @param key: 此源的唯一标识符
-- @param default: 源超时或质量不佳时的默认值
-- @param delay: 特于此源的可选延迟
-- @param timeout: 特于此源的可选超时
---
function concat:add(key, default, delay, timeout)
	self._source[key] = {
		name = key,
		default = default,
		value = default,
		delay = delay,
		timeout = timeout,
		last = ioe.time()
	}
end

---
-- 从源更新值
-- @param key: 源标识符
-- @param value: 新值
-- @param timestamp: 可选的值时间戳
-- @param quality: 可选的质量标志（0=良好，非零=不良）
---
function concat:update(key, value, timestamp, quality)
	local timestamp = timestamp or ioe.time()
	local quality = quality == nil and 0 or quality

	local item = self._source[key]
	assert(item)

	item.value = quality == 0 and value or item.default
	item.timestamp = timestamp
	item.last = ioe.time()

	local delay = item.delay or self._delay

	if delay > 0 then
		if self._delay_exec_cancel then
			self._delay_exec_cancel()
		end
		self._delay_exec_cancel = cancelable_timeout(delay, function()
			self._delay_exec_cancel = nil
			self:call_calc()
		end)
	end
end

---
-- 用收集的值调用计算函数
-- 检查超时并在需要时应用默认值
---
function concat:call_calc()
	--print('call_calc')
	local values = {}
	local now = ioe.time()
	for k, v in pairs(self._source) do
		local timeout = v.timeout or self._timeout
		if timeout and v.value and (now - v.last) * 1000 > timeout then
			v.value = v.default
		end

		if self._need_all and not v.value then
			return
		end

		values[k] = v.value
	end

	self._calc(values)
end

return concat
