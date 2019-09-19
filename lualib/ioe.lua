local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local tls_loaded, tls = pcall(require, "http.tlshelper")

local _M = {}

-- System ID
_M.id = function()
	return dc.get("CLOUD", "ID") or dc.wait("SYS", "ID")
end

_M.hw_id = function()
	return dc.wait("SYS", "ID")
end

_M.beta = function()
	return dc.get("SYS", "USING_BETA")
end

_M.set_beta = function(value)
	dc.set("SYS", "USING_BETA", value)
end

_M.auth_code = function()
	return dc.get("SYS", "AUTH_CODE")
end

_M.set_auth_code = function(value)
	dc.set("SYS", "AUTH_CODE", value)
end

_M.make_url = function(url)
	local protocol, _url = string.match(url, "^([^:]+)://(.+)$")
	if protocol then
		return url
	end
	return url
	--return tls_loaded and "https://"..url
end

_M.pkg_host_url = function()
	return _M.make_url(dc.get("SYS", "PKG_HOST_URL"))
end

_M.set_pkg_host_url = function(value)
	dc.set("SYS", "PKG_HOST_URL", value)
end

_M.cnf_host_url = function()
	return _M.make_url(dc.get("SYS", "CNF_HOST_URL"))
end

_M.set_cnf_host_url = function(value)
	dc.set("SYS", "CNF_HOST_URL", value)
end

_M.cfg_auto_upload = function()
	return dc.get('SYS', "CFG_AUTO_UPLOAD")
end

_M.set_cfg_auto_upload = function(value)
	dc.set('SYS', 'CFG_AUTO_UPLOAD', value)
end

_M.time = skynet.time
_M.starttime = skynet.starttime

--[[
_M.datacenter = dc
_M.skynet = skynet
_M.cjson = require 'cjson'
_M.curl = require 'curl'
_M.serialchannel = require 'serialchannel'
_M.socketchannel = require 'socketchannel'
_M.basexx = require 'basexx'
]]--

_M.abort_prepare = function()
	local appmgr = snax.uniqueservice("appmgr")
	if appmgr then
		appmgr.post.close_all("FreeIOE is aborting!!!")
	end
end

_M.abort = function(timeout)
	_M.abort_prepare()

	local timeout = timeout or 5000
	skynet.timeout(timeout / 10, function()
		skynet.abort()
	end)
end

return _M
