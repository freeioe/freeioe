--- SiriDB数据库客户端模块
-- @module db.siridb.database
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 提供SiriDB数据库的数据写入和查询功能，支持qpack压缩

local cjson = require 'cjson.safe'
local class = require 'middleclass'
local restful = require 'http.restful'
local sdata = require 'db.siridb.data'

--- 尝试加载qpack模块
local has_qpack, qpack = pcall(require, 'qpack.safe')

local database = class('db.siridb.database')

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
-- @param options 配置选项表
-- @param dbname 可选，数据库名称
-- @return 数据库客户端实例
function database:initialize(options, dbname)
	self._options = assert(options)
	local host = option_to_url(self._options)
	local auth = {options.username or 'iris', options.password or 'siri'}
	self._rest = restful:new(host, self._options.timeout, nil, auth)
	self._ts = options.time_precision or 'ms'
	self._db = dbname or options.db or 'test'
end

--- 获取时间精度
-- @return string 时间精度（s/ms/us/ns）
function database:time_precision()
	return self._ts
end

--- 获取数据库名称
-- @return string 数据库名称
function database:dbname()
	return self._db
end

--- 获取配置选项（未实现）
function database:options()
end

--- 发送POST请求（支持qpack压缩）
-- @param url 请求URL
-- @param params 查询参数
-- @param data 请求数据
-- @return table|nil 响应状态码
-- @return string|nil 响应体
function database:post(url, params, data)
	if not has_qpack then
		return self._rest:post(url, params, data)
	end

	local body = nil
	if data then
		local str, err = qpack.encode(data)
		if not str then
			return nil, err
		end
		body = str
	end

	return self._rest:post(url, params, body, 'application/qpack')
end

--- 发送GET请求（支持qpack压缩）
-- @param url 请求URL
-- @param params 查询参数
-- @param data 请求数据
-- @return table|nil 响应状态码
-- @return string|nil 响应体
function database:get(url, params, data)
	if not has_qpack then
		return self._rest:get(url, params, data)
	end

	local body = nil
	if data then
		local str, err = qpack.encode(data)
		if not str then
			return nil, err
		end
		body = str
	end
	return self._rest:get(url, params, body, 'application/qpack')
end

--- 插入数据
-- @param data 数据对象
-- @param auto_clean 是否自动清理已编码的数据
-- @return boolean|nil 成功返回true
-- @return string|nil 错误信息
function database:insert(data, auto_clean)
	assert(data, "data missing")
	assert(data.encode, "data object incorrect")
	local status, body = self:post('/insert/'..self._db, nil, data:encode(self._ts, auto_clean))
	if status == 200 then
		return true
	else
		return nil, tostring(body)
	end
end

--- 插入单个时间序列
-- @param series 时间序列对象
-- @param auto_clean 是否自动清理已编码的数据
-- @return boolean|nil 成功返回true
-- @return string|nil 错误信息
function database:insert_series(series, auto_clean)
	assert(series, "series missing")
	local data = sdata:new()
	data:add_series(series:series_name(), series)
	return self:insert(data, auto_clean)
end

--- 执行查询
-- @param query SiriDB查询语句
-- @param time_precision 可选，时间精度，默认使用数据库配置
-- @return table|nil 查询结果数据，失败返回nil
-- @return string|nil 错误信息
-- @return number 状态码
-- @description 查询时间范围[start, end)，包含开始时刻的数据但不包含结束时刻
function database:query(query, time_precision)
	assert(query, "query string missing")
	local status, body = self:post('/query/'..self._db, nil, {
		q = query,
		t = time_precision or self._ts
	})
	if status == 200 then
		local pk = has_qpack and qpack or cjson
		local data, err = pk.decode(body)
		if not data then
			return nil, err
		end
		return data
	end
	return nil, tostring(body), status
end

--- 执行SQL语句
-- @param sql SQL语句
-- @return table|nil 查询结果数据，失败返回nil
-- @return string|nil 错误信息
-- @return number 状态码
function database:exec(sql)
	assert(sql, "query string missing")
	local status, body = self:post('/query/'..self._db, nil, {q = sql})
	if status == 200 then
		local pk = has_qpack and qpack or cjson
		local data, err = pk.decode(body)
		if not data then
			return nil, err
		end
		return data
	end
	return nil, tostring(body), status
end

return database
