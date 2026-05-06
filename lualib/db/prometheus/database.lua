--- Prometheus数据库客户端模块
-- @module db.prometheus.database
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 提供Prometheus HTTP API客户端功能，支持数据写入和查询

local class = require 'middleclass'
local cjson = require 'cjson.safe'
local sdata = require 'db.prometheus.data'
local restful = require 'http.restful'

local database = class('db.prometheus.database')

--- 将配置选项转换为URL
-- @param options 配置选项表
-- @return string 完整的URL字符串
local function option_to_url(options)
	local proto = 'http'
	if options.ssl then
		proto = 'https'
	end
	local host = options.host or '127.0.0.1'
	local port = tonumber(options.port) or 9020

	return string.format('%s://%s:%d', proto, host, port)
end

--- 初始化数据库客户端
-- @param options 配置选项表，包含host、port、ssl、username、password、url、job、instance等
-- @return 数据库客户端实例
function database:initialize(options)
	self._options = assert(options)
	local host = option_to_url(options)
	local auth = options.username and {options.username, options.password} or nil
	self._rest = restful:new(host, self._options.timeout, nil, auth)

	local url = self._options.url or '/metric'
	if options.job then
		url = url .. '/job/' .. options.job
	end
	if options.instance then
		url = url ..'/instance/' .. options.instance
	end
	self._url = url
end

--- 插入数据到Prometheus
-- @param data 数据对象
-- @param auto_clean 是否自动清理已编码的数据
-- @return boolean|nil 成功返回true
-- @return string|nil 错误信息
function database:insert(data, auto_clean)
	local sts, body = self._rest:post(self._url, nil, data:encode(auto_clean))
	if tonumber(sts) == 204 then
		return true
	end
	return nil, tostring(body)
end

--- 插入单个指标
-- @param metric 指标对象
-- @param auto_clean 是否自动清理已编码的数据
-- @return boolean|nil 成功返回true
-- @return string|nil 错误信息
function database:insert_metric(metric, auto_clean)
	local data = sdata:new()
	data:add_metric(metric)
	return self:insert(data, auto_clean)
end

--- 执行即时查询
-- @param query PromQL查询语句
-- @param time 可选，查询时间点（RFC3339格式或Unix时间戳）
-- @param timeout 可选，查询超时时间
-- @return table|nil 查询结果数据，失败返回nil
-- @return string|nil 错误信息
-- @return string|nil 错误类型
function database:query(query, time, timeout)
	local sts, body = self._rest:post('/api/v1/query', {
		query = query,
		time = time,
		timeout = timeout
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		if data.status == 'success' then
			return data.data
		end
		return nil, data.error, data.errorType
	end
	return nil, tostring(body)
end

--- 执行范围查询
-- @param query PromQL查询语句
-- @param start 开始时间（RFC3339格式或Unix时间戳）
-- @param etime 结束时间（RFC3339格式或Unix时间戳）
-- @param step 查询步长（持续时间或浮点数）
-- @param timeout 可选，查询超时时间
-- @return table|nil 查询结果数据，失败返回nil
-- @return string|nil 错误信息
-- @return string|nil 错误类型
function database:query_range(query, start, etime, step, timeout)
	local sts, body = self._rest:post('/api/v1/query_range', {
		query = query,
		start = start,
		['end'] = etime,
		step = step,
		timeout = timeout
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		if data.status == 'success' then
			return data.data
		end
		return nil, data.error, data.errorType
	end
	return nil, tostring(body)
end

--- 查询时间序列
-- @param match 匹配器，如 '{__name__="metric_name"}'
-- @param start 开始时间（RFC3339格式或Unix时间戳）
-- @param etime 结束时间（RFC3339格式或Unix时间戳）
-- @return table|nil 查询结果数据，失败返回nil
-- @return string|nil 错误信息
-- @return string|nil 错误类型
function database:query_series(match, start, etime)
	local sts, body = self._rest:post('/api/v1/series', {
		match = match,
		start = start,
		['end'] = etime
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		if data.status == 'success' then
			return data.data
		end
		return nil, data.error, data.errorType
	end
	return nil, tostring(body)
end

--- 查询标签
-- @param match 匹配器
-- @param start 开始时间（RFC3339格式或Unix时间戳）
-- @param etime 结束时间（RFC3339格式或Unix时间戳）
-- @return table|nil 查询结果数据，失败返回nil
-- @return string|nil 错误信息
-- @return string|nil 错误类型
function database:query_labels(match, start, etime)
	local sts, body = self._rest:post('/api/v1/labels', {
		match = match,
		start = start,
		['end'] = etime
	})
	if sts == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		if data.status == 'success' then
			return data.data
		end
		return nil, data.error, data.errorType
	end
	return nil, tostring(body)
end

return database
