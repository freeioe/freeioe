--- SiriDB数据容器模块
-- @module db.siridb.data
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 用于管理多个SiriDB时间序列的数据容器

local skynet = require 'skynet'
local class = require 'middleclass'

local data = class('db.siridb.data')

--- 初始化数据容器
function data:initialize()
	self._list = {}
end

--- 编码所有时间序列
-- @param time_precision 时间精度（s/ms/us/ns）
-- @param auto_clean 是否自动清理已编码的数据
-- @return table 编码后的数据表
function data:encode(time_precision, auto_clean)
	local data = {}
	for k, v in pairs(self._list) do
		data[k] = v:encode(time_precision, auto_clean)
	end
	return data
end

--- 添加时间序列
-- @param name 时间序列名称
-- @param series 时间序列对象
function data:add_series(name, series)
	assert(name)
	assert(series)
	assert(self._list[name] == nil)
	self._list[name] = series
end

--- 获取所有时间序列
-- @return table 时间序列表
function data:list()
	return self._list
end

return data
