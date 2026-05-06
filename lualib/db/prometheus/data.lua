--- Prometheus数据容器模块
-- @module db.prometheus.data
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 用于管理多个Prometheus指标的数据容器

local class = require 'middleclass'

local data = class('db.prometheus.data')

--- 初始化数据容器
function data:initialize()
	self._list = {}
end

--- 添加指标到容器
-- @param metric 指标对象
function data:add_metric(metric)
	table.insert(self._list, metric)
end

--- 编码所有指标为Prometheus文本格式
-- @param auto_clean 是否在编码后自动清理数据
-- @return string Prometheus文本格式的字符串
function data:encode(auto_clean)
	local data = {}
	for _, v in ipairs(self._list) do
		local lines = v:encode(auto_clean)
		table.move(lines, 1, #lines, #data + 1, data)
	end

	return table.concat(data, '\n')
end

return data
