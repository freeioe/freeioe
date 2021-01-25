local _M = {}

local skynet = require "skynet"
local socket = require "skynet.socket"
local crypt = require "skynet.crypt"
local httpc = require "http.httpc"

local encode_base64 = crypt.base64encode

local str_fmt  = string.format
local HTTP_NO_CONTENT = 204


_M.version = "0.2"

local udp_handler = nil

function _M.init_udp()
	udp_handler = socket.udp(function(str, from)
		print("recv addr:", socket.udp_address(from))
	end)
end

function _M.write_udp(msg, params)
	if not udp_handler then
		_M.init_udp()
	end
	assert(udp_handler)
	return socket.sendto(udp_handler,  params.host, params.port, msg)
end

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

function _M.validate_options(opts)
	if type(opts) ~= 'table' then
		return false, 'opts must be a table'
	end

	opts.host      = opts.host or '127.0.0.1'
	opts.port      = opts.port or 8086
	opts.db        = opts.db or 'influx'
	opts.hostname  = opts.hostname or opts.host
	opts.proto     = opts.proto or 'http'
	opts.precision = opts.precision or 'ms'
	opts.ssl       = opts.ssl or false
	opts.auth      = opts.auth or nil

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
