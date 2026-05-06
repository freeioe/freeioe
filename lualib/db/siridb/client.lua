--- SiriDB HTTP客户端模块
-- @module db.siridb.client
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 提供SiriDB数据库管理的HTTP客户端接口

local class = require 'middleclass'
local restful = require 'http.restful'
local cjson = require 'cjson.safe'

local client = class('db.siridb.http')

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

--- 初始化客户端
-- @param options 配置选项表，包含host、port、ssl、username、password等
function client:initialize(options)
	self._options = options
	local host = option_to_url(self._options)
	local auth = {options.username or 'sa', options.password or 'siri'}
	self._rest = restful:new(host, self._options.timeout, nil, auth)
end

--- 发送POST请求
-- @param url 请求URL
-- @param params 查询参数
-- @param data 请求体数据
-- @return table|nil 响应数据（JSON解码），失败返回nil
-- @return string|nil 响应体或错误信息
function client:post(url, params, data)
	local sts, body = self._rest:post(url, params, data)
	if tonumber(sts) == 200 then
		return cjson.decode(body), body
	end
	return nil, body
end

--- 发送GET请求
-- @param url 请求URL
-- @param params 查询参数
-- @param data 请求数据
-- @return table|nil 响应数据（JSON解码），失败返回nil
-- @return string|nil 错误信息
function client:get(url, params, data)
	local sts, body = self._rest:get(url, params, data)
	if tonumber(sts) == 200 then
		local data, err = cjson.decode(body)
		if not data then
			return nil, err
		end
		return data
	end
	return nil, body
end

--- 创建新数据库
-- @param dbname 数据库名称
-- @param time_precision 可选，时间精度（s/ms/us/ns），默认'ms'
-- @param buffer_size 可选，缓冲区大小，默认1024
-- @param duration_num 可选，持续时间数量
-- @param duration_log 可选，持续时间日志
-- @return boolean|nil 成功返回true
-- @return string|nil 错误信息
function client:new_database(dbname, time_precision, buffer_size, duration_num, duration_log)
	assert(dbname)
	local data = {
		dbname = dbname,
		time_precision = time_precision or 'ms',
		buffer_size = tonumber(buffer_size) or 1024,
		duration_num = duration_num,
		duration_log = duration_log,
	}
	local r, err = self:post('/new-database', nil, data)
	if r and r == 'OK' then
		return true
	end
	return nil, err or r
end

--- 创建新账户
-- @param user 用户名
-- @param passwd 密码
-- @return table|nil 响应数据，失败返回nil
-- @return string|nil 错误信息
function client:new_account(user, passwd)
	assert(user, "User missing")
	assert(passwd, "Password missing")
	return self:post('/new-account', nil, {
		account = user,
		password = passwd
	})
end

--- 修改密码
-- @param user 用户名
-- @param password 新密码
-- @return table|nil 响应数据，失败返回nil
-- @return string|nil 错误信息
function client:change_password(user, password)
	assert(user, "User missing")
	assert(passwd, "Password missing")
	return self:post('/change-password', nil, {
		account = user,
		password = passwd
	})
end

--- 删除账户
-- @param user 用户名
-- @return table|nil 响应数据，失败返回nil
-- @return string|nil 错误信息
function client:drop_account(user)
	assert(user, "User missing")
	return self:post('/drop-account', nil, {
		account = user
	})
end

--- 创建连接池
-- @param dbname 数据库名称
-- @param user 用户名
-- @param passwd 密码
-- @param host 主机地址
-- @param port 端口号
-- @return table|nil 响应数据，失败返回nil
-- @return string|nil 错误信息
function client:new_pool(dbname, user, passwd, host, port)
	assert(dbname, 'dbname missing')
	return self:post('/new-pool', nil, {
		dbname = dbname,
		username = user,
		password = passwd,
		host = host,
		port = port
	})
end

--- 创建副本
-- @param dbname 数据库名称
-- @param user 用户名
-- @param passwd 密码
-- @param host 主机地址
-- @param port 端口号
-- @param pool 连接池名称
-- @return table|nil 响应数据，失败返回nil
-- @return string|nil 错误信息
function client:new_replica(dbname, user, passwd, host, port, pool)
	assert(dbname, 'dbname missing')
	return self:post('/new-pool', nil, {
		dbname = dbname,
		username = user,
		password = passwd,
		host = host,
		port = port,
		pool = pool
	})
end

--- 删除数据库
-- @param dbname 数据库名称
-- @param ignore_offline 是否忽略离线状态
-- @return table|nil 响应数据，失败返回nil
-- @return string|nil 错误信息
function client:drop_database(dbname, ignore_offline)
	assert(dbname, "dbname missing")
	return self:post('/drop-account', nil, {
		database = dbname,
		ignore_offline = ignore_offline and true or false
	})
end

--- 获取服务器版本
-- @return string|nil 版本号，失败返回nil
-- @return string|nil 错误信息
function client:get_version()
	local data, err = self:get('/get-version')
	if data then
		return data[1]
	end
	return nil, err
end

--- 获取所有账户
-- @return table|nil 账户列表，失败返回nil
function client:get_accounts()
	return self:get('/get-accounts')
end

--- 获取所有数据库
-- @return table|nil 数据库列表，失败返回nil
function client:get_databases()
	return self:get('/get-databases')
end

return client
