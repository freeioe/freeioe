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

_M.mode = function()
	return tonumber(dc.get("SYS", "WORK_MODE")) or 0
end

_M.set_mode = function(value)
	dc.set("SYS", "WORK_MODE", tonumber(value) or 0)
end

_M.MODE = {
	NORMAL = 0,
	LOCKED = 1,
}

_M.cloud_host = function()
	return dc.wait("CLOUD", "HOST")
end

_M.set_cloud_host = function(value)
	dc.set("CLOUD", "HOST", value)
end

_M.cloud_port = function()
	return dc.wait("CLOUD", "PORT")
end

_M.set_cloud_port = function(value)
	dc.set("CLOUD", "PORT", value)
end

_M.cloud_secret = function()
	return dc.wait("CLOUD", "SECRET")
end

_M.set_cloud_secret = function(value)
	dc.set("CLOUD", "SECRET", value)
end

_M.set_data_cache = function(enable)
	dc.set("CLOUD", "DATA_CACHE", enable == true or enable == 1)
end

_M.data_cache = function()
	return dc.get("CLOUD", "DATA_CACHE")
end

_M.auth_code = function()
	return dc.get("SYS", "AUTH_CODE")
end

_M.set_auth_code = function(value)
	dc.set("SYS", "AUTH_CODE", value)
end

_M.set_online_check_ip = function(ip)
	local sysinfo = require 'utils.sysinfo'
	return sysinfo.set_online_check_ip(ip)
end

_M.make_url = function(url)
	local protocol, _url = string.match(url, "^([^:]+)://(.+)$")
	if protocol then
		return url
	end
	return url
	--return tls_loaded and "https://"..url
end

_M.pkg_ver = function()
	local ver = dc.get("SYS", "PKG_VER")
	if not ver then
		return 1
	end
	return tonumber(ver)
end

_M.set_pkg_ver = function(value)
	dc.set("SYS", "PKG_VER", value)
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

_M.developer_mode = function()
	return os.getenv("IOE_DEVELOPER_MODE") or dc.get('SYS', 'DEVELOPER_MODE')
end

_M.cloud_status = function()
	local cloud = snax.uniqueservice("cloud")
	local online, last, msg = cloud.req.get_status()
	return online, last, msg
end

_M.now = function()
	return skynet.now() * 10 --- ms
end
_M.time = skynet.time
_M.starttime = skynet.starttime
_M.hpc = skynet.hpc

--[[
_M.datacenter = dc
_M.skynet = skynet
_M.cjson = require 'cjson'
_M.curl = require 'curl'
_M.serialchannel = require 'serialchannel'
_M.socketchannel = require 'socketchannel'
_M.basexx = require 'basexx'
]]--

_M.abort = function(timeout)
	local timeout = timeout or 5
	skynet.call(".cfg", "lua", "save")
	skynet.call(".upgrader", "lua", "system_quit", id, {delay=timeout})
end

_M.env = {
	set = function(...)
		dc.set("__IOE_ENV", ...)
	end,
	get = function(...)
		return dc.get("__IOE_ENV", ...)
	end,
	wait = function(...)
		return dc.wait("__IOE_ENV", ...)
	end,
}

return _M
