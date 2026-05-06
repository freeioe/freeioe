--- SiriDB时间序列模块
-- @module db.siridb.series
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 定义和管理SiriDB时间序列，支持多种值类型

local skynet = require 'skynet'
local class = require 'middleclass'
local log = require 'utils.logger'.new()

local series = class('db.siridb.series')

--- 时间精度映射表
local _MAP_TS = {
	s = 1,           -- 秒
	ms = 1000,       -- 毫秒
	us = 1000000,    -- 微秒
	ns = 1000000000  -- 纳秒
}

--- 初始化时间序列
-- @param name 时间序列名称
-- @param value_type 值类型：int（整数）、float（浮点数）、string（字符串）
function series:initialize(name, value_type)
	self._name = name
	self._value_type = value_type or 'float'
	self._values = {}
end

--- 获取时间序列名称
-- @return string 时间序列名称
function series:series_name()
	return self._name
end

--- 获取值类型
-- @return string 值类型
function series:value_type()
	return self._value_type
end

--- 清空所有值
function series:clean()
	self._values = {}
end

--- 编码时间序列数据
-- @param time_precision 时间精度（s/ms/us/ns）
-- @param auto_clean 是否自动清理已编码的数据
-- @return table 编码后的数据数组
function series:encode(time_precision, auto_clean)
	local ts = _MAP_TS[time_precision]

	local data = {}
	for k, v in ipairs(self._values) do
		data[#data + 1] = {math.floor(v[1] * ts), v[2]}
	end
	if auto_clean then
		self:clean()
	end
	return data
end

--- 添加值到时间序列
-- @param value 值（根据value_type自动转换）
-- @param timestamp 可选，时间戳，默认使用当前时间
function series:push_value(value, timestamp)
	local vt = self._value_type
	if vt == 'int' then
		value = math.floor(tonumber(value)) or 0
	elseif vt == 'string' then
		value = tostring(value) or 'ERROR_STRING'
	else
		value = (tonumber(value) or 0) + 0.0
	end
	-- log.debug('SIRIDB.series', self._name, self._value_type, value, timestamp)
	table.insert(self._values, {timestamp or skynet.time(), value})
end

--- 获取所有值
-- @return table 值数组
function series:values()
	return self._values
end

return series
