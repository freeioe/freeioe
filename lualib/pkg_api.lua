local skynet = require 'skynet'
local datacenter = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local httpdown = require 'httpdown'

local _M = {}

function _M.pkg_check_update(pkg_host, app, version, beta)
	local version = tonumber(version)
	local url = '/pkg/check_update'
	local query = { app = app }
	if beta then
		query.beta = 1
	end
	local status, header, body = httpdown.get(pkg_host, url, {}, query)
	local ret = {}
	if status == 200 then
		local msg, err = cjson.decode(body)
		local ver = tonumber( (msg and msg.message) or 0)
		if ver > version then
			ret.version = ver
		else
			ret.message = "No newer version"
		end
	else
		ret.message = body
	end
	return ret
end

function _M.pkg_enable_beta(pkg_host, sys_id)
	local url = '/pkg/enable_beta'
	local status, header, body = httpdown.get(pkg_host, url, {Accpet="application/json"}, {sn=sys_id})
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		local val = tonumber(msg.message or 0)
		ret.beta = val > 0
	else
		ret.message = body
	end
	return ret
end

return _M
