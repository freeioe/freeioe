local skynet = require 'skynet'
local datacenter = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local httpdown = require 'httpdown'

local _M = {}

local api_header = {
	Accpet="application/json"
}

function _M.pkg_check_update(pkg_host, app, beta)
	local url = '/pkg/check_update'
	local query = { app = app }
	if beta then
		query.beta = 1
	end
	local status, header, body = httpdown.get(pkg_host, url, api_header, query)
	local ret = {}
	if status == 200 then
		local msg, err = cjson.decode(body)
		if not msg.message then
			return nil, "No version found!"
		end
		return msg.message.version, msg.message.beta == 1
	else
		return nil, body
	end
end

function _M.pkg_enable_beta(pkg_host, sys_id)
	local url = '/pkg/enable_beta'
	local status, header, body = httpdown.get(pkg_host, url, api_header, {sn=sys_id})
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		local val = tonumber(msg.message or 0)
		return val
	else
		return nil, body
	end
end

function _M.pkg_check_version(pkg_host, app, version)
	local version = version
	if type(version) == 'number' then
		version = string.format("%d", version)
	end
	local url = '/pkg/check_version'
	local status, header, body = httpdown.get(pkg_host, url, api_header, {app=app, version=version})
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		if not msg.message then
			return nil, "Version not valided"
		end
		return msg.message
	else
		return nil, body
	end
end

return _M
