--- InfluxDB工具模块
-- @module db.influxdb.util
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 提供HTTP/UDP写入、查询和选项验证功能

local _M = {}

local skynet = require "skynet"
local socket = require "skynet.socket"
local crypt = require "skynet.crypt"
local httpc = require "http.httpc"

local encode_base64 = crypt.base64encode

local str_fmt  = string.format
local HTTP_NO_CONTENT = 204


_M.version = "0.2"

--- UDP处理句柄
local udp_handler = nil

--- 初始化UDP连接
function _M.init_udp()
	udp_handler = socket.udp(function(str, from)
		print("recv addr:", socket.udp_address(from))
	end)
end

--- 通过UDP写入数据
-- @param msg 要写入的消息
-- @param params 参数表，包含host和port
-- @return boolean 成功返回true
function _M.write_udp(msg, params)
	if not udp_handler then
		_M.init_udp()
	end
	assert(udp_handler)
	return socket.sendto(udp_handler,  params.host, params.port, msg)
end

--- 通过HTTP写入数据
-- @param msg 要写入的消息
-- @param params 参数表
-- @return boolean 成功返回true
-- @return string|nil 响应体或错误信息
function _M.write_http(msg, params)
	local scheme   = 'http'
	if params.ssl then
		scheme     = 'https'
	end

	local header = {}
	if params.auth then
		header.Authorization = str_fmt("Basic %s", encode_base64(params.auth))
	end

	local recvheader = {}

	local host  = str_fmt("%s://%s:%s", scheme, params.host, params.port)
	local url = '/write' .. '?' .. 'db=' .. params.db .. '&' .. 'precision=' .. params.precision
	local method  = "POST"
	local ok, status, body = pcall(httpc.request, method, host, url, recvheader, header, msg)
	if status == HTTP_NO_CONTENT then
		return true, body
	else
		return false, status
	end
end

--- 通过HTTP执行查询
-- @param params 参数表，包含db、precision、username、password、query等
-- @return boolean 成功返回true
-- @return string|nil 响应体或错误信息
function _M.query_http(params)
	local scheme = 'http'
	if prarams.ssl then
		scheme = 'https'
	end

	local header = {}
	if params.auth then
		header.Authorization = str_fmt("Basic %s", encode_base64(params.auth))
	end

	local recvheader = {}

	local host  = str_fmt("%s://%s:%s", scheme, params.host, params.port)
	local url = '/query' .. '?' .. 'db=' .. params.db .. '&' .. 'precision=' .. params.precision
	if params.username then
		url = url .. 'u='..params.username
	end
	if params.password then
		url = url .. 'p='..params.username
	end
	url = url..'q='..params.query
	local method  = "POST"
	local ok, status, body = pcall(httpc.request, method, host, url, recvheader, header, msg)
	if status == HTTP_NO_CONTENT then
		return true, body
	else
		return false, status
	end
end

--- 验证配置选项
-- @param opts 配置选项表
-- @return boolean 验证通过返回true
-- @return string|nil 错误信息
function _M.validate_options(opts)
	if type(opts) ~= 'table' then
		return false, 'opts must be a table'
	end

	-- 设置默认值
	opts.host      = opts.host or '127.0.0.1'
	opts.port      = opts.port or 8086
	opts.db        = opts.db or 'influx'
	opts.hostname  = opts.hostname or opts.host
	opts.proto     = opts.proto or 'http'
	opts.precision = opts.precision or 'ms'
	opts.ssl       = opts.ssl or false
	opts.auth      = opts.auth or nil

	-- 验证各参数类型和值
	if type(opts.host) ~= 'string' then
		return false, 'invalid host'
	end
	if type(opts.port) ~= 'number' or opts.port < 0 or opts.port > 65535 then
		return false, 'invalid port'
	end
	if type(opts.db) ~= 'string' or opts.db == '' then
		return false, 'invalid db'
	end
	if type(opts.hostname) ~= 'string' then
		return false, 'invalid hostname'
	end
	if type(opts.proto) ~= 'string' or (opts.proto ~= 'http' and opts.proto ~= 'udp') then
		return false, 'invalid proto ' .. tostring(opts.proto)
	end
	if type(opts.precision) ~= 'string' then
		return false, 'invalid precision'
	end
	if type(opts.ssl) ~= 'boolean' then
		return false, 'invalid ssl'
	end
	if opts.auth and type(opts.auth) ~= 'string' then
		return false, 'invalid auth'
	end
	return true
end

return _M
