--- Prometheus指标模块
-- @module db.prometheus.metric
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 定义和管理Prometheus指标，支持标签和多值记录

local skynet = require 'skynet'
local class = require 'middleclass'

local metric = class('db.prometheus')

--- 初始化指标
-- @param name 指标名称
-- @param labels 可选，标签表
-- @param typ 可选，指标类型（gauge、counter等）
-- @param help 可选，指标帮助文本
function metric:initialize(name, labels, typ, help)
	assert(name)
	self._name = name
	self._labels = labels or {}
	self._typ = typ
	self._help = help
	self._values = {}
end

--- 获取指标名称
-- @return string 指标名称
function metric:metric_name()
	return self._name
end

--- 获取标签表
-- @return table 标签表
function metric:labels()
	return self._labels
end

--- 设置标签值
-- @param name 标签名
-- @param value 标签值
function metric:set_label(name, value)
	self._labels[name] = value
end

--- 添加值到指标
-- @param value 数值（可以是数字或数字字符串）
-- @param timestamp 可选，时间戳，默认使用当前时间
function metric:push_value(value, timestamp)
	if type(value) == 'string' then
		value = assert(tonumber(value))
	end
	table.insert(self._values, {
		value = value,
		timestamp = timestamp or skynet.time()
	})
end

--- 获取所有值
-- @return table 值数组
function metric:values()
	return self._values
end

--- 清空所有值
function metric:clean()
	self._values = {}
end

--- 编码单个值和时间为Prometheus格式
-- @param value 数值
-- @param timestamp 时间戳
-- @return string Prometheus格式的行
function metric:_encode_value(value, timestamp)
	local val = tostring(value)
	local ts = math.floor(timestamp * 1000)
	local labels = self._labels
	local llist = {}
	for k, v in pairs(labels) do
		local val = v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
		llist[#llist + 1] = string.format('%s="%s"', k, val)
	end
	if #llist == 0 then
		return string.format('%s %s %d', self._name, val, ts)
	end
	return string.format("%s{%s} %s %d", self._name, table.concat(llist, ','), val, ts)
end

--- 编码所有值为Prometheus格式
-- @return table Prometheus格式行数组
function metric:_encode_values()
	local list = {}
	for _, v in ipairs(self._values) do
		list[#list + 1] = self:_encode_value(v.value, v.timestamp)
	end
	return list
end

--- 编码指标为Prometheus文本格式
-- @param auto_clean 是否在编码后自动清理数据
-- @return table Prometheus格式行数组
function metric:encode(auto_clean)
	local lines = self:_encode_values()
	if self._help then
		table.insert(lines, 1, '# HELP '..self._name..' '..self._help)
	end
	if self._typ then
		table.insert(lines, 1, '# TYPE '..self._name..' '..self._typ)
	end
	if auto_clean then
		self:clean()
	end
	return lines
end

--- 从Prometheus格式解码（未实现）
-- @param lines Prometheus格式行
-- @return nil
function metric:decode(lines)
	assert(nil, "Not implemented")
end

return metric
