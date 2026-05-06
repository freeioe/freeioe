--- VictoriaMetrics数据库客户端模块
-- @module db.victoria.database
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 提供VictoriaMetrics的HTTP API客户端功能

local class = require 'middleclass'
local cjson = require 'cjson.safe'
local restful = require 'http.restful'

local database = class('db.victoria.database')

--- 将配置选项转换为URL
-- @param options 配置选项表
-- @return string 完整的URL字符串
local function option_to_url(options)
	local proto = 'http'
	if options.ssl then
		proto = 'https'
	end
	local host = options.host or '127.0.0.1'
	local port = tonumber(options.port) or 8428

	return string.format('%s://%s:%d', proto, host, port)
end

--- 初始化数据库客户端
-- @param options 配置选项表，包含host、port、ssl、username、password等
-- @return 数据库客户端实例
function database:initialize(options)
	self._options = assert(options)
	local host = option_to_url(options)
	local auth = options.username and {options.username, options.password} or nil
	self._rest = restful:new(host, self._options.timeout, nil, auth)
end

--- 导出时间序列数据
-- @param match 匹配器，如 '{__name__="metric_name"}'
-- @param start 开始时间（Unix时间戳或RFC3339格式）
-- @param etime 结束时间（Unix时间戳或RFC3339格式）
-- @param max_rows_per_line 可选，每行最大数据点数
-- @return table|nil 导出的数据，失败返回nil
-- @return string|nil 错误信息
function database:export(match, start, etime, max_rows_per_line)
	local sts, body = self._rest:post('/api/v1/export', {
		match = match,
		start = start,
		['end'] = etime,
		max_rows_per_line = max_rows_per_line
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		return data
	end
	return nil, tostring(body)
end

return database
