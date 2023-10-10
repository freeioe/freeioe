--[[
--  FreeIOE System information interface
--]]
local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local tls_loaded, tls = pcall(require, "http.tlshelper")

local _M = {}

-- System ID used for IOE Cloud, which may diff with hardware ID
_M.id = function()
	return dc.get("CLOUD", "ID") or dc.wait("SYS", "ID")
end

-- Hardware ID
_M.hw_id = function()
	return dc.wait("SYS", "ID")
end

-- Beta mode
_M.beta = function()
	return dc.get("SYS", "USING_BETA")
end

-- Set beta mode
_M.set_beta = function(value)
	dc.set("SYS", "USING_BETA", value)
end

-- Work mode
_M.mode = function()
	return tonumber(dc.get("SYS", "WORK_MODE")) or 0
end

-- Set work mode
_M.set_mode = function(value)
	dc.set("SYS", "WORK_MODE", tonumber(value) or 0)
end

-- Mode enum
_M.MODE = {
	NORMAL = 0, --- Normal mode
	LOCKED = 1, --- Locked mode (system is read-only)
}

-- Cloud host address
_M.cloud_host = function()
	return dc.wait("CLOUD", "HOST")
end

-- Set cloud host address
_M.set_cloud_host = function(value)
	dc.set("CLOUD", "HOST", value)
end

-- Get cloud connection port, normally 1883
_M.cloud_port = function()
	return dc.wait("CLOUD", "PORT")
end

-- Set cloud connection port
_M.set_cloud_port = function(value)
	dc.set("CLOUD", "PORT", value)
end

-- Get cloud secret
_M.cloud_secret = function()
	return dc.wait("CLOUD", "SECRET")
end

-- Set cloud secret
_M.set_cloud_secret = function(value)
	dc.set("CLOUD", "SECRET", value)
end

-- Set data cache option (enable: true, disable: false)
_M.set_data_cache = function(enable)
	dc.set("CLOUD", "DATA_CACHE", enable == true or enable == 1)
end

-- Get data cache option
_M.data_cache = function()
	return dc.get("CLOUD", "DATA_CACHE")
end

-- Get cloud auth code
_M.auth_code = function()
	return dc.get("SYS", "AUTH_CODE")
end

-- Set cloud auth code
_M.set_auth_code = function(value)
	dc.set("SYS", "AUTH_CODE", value)
end

-- Set online check IP address (using ping)
_M.set_online_check_ip = function(ip)
	local sysinfo = require 'utils.sysinfo'
	return sysinfo.set_online_check_ip(ip)
end

---
-- Get only url address
_M.make_url = function(url)
	local protocol, _url = string.match(url, "^([^:]+)://(.+)$")
	if protocol then
		return url
	end
	return url
	--return tls_loaded and "https://"..url
end

-- Get app store server address
_M.pkg_host_url = function()
	return _M.make_url(dc.get("SYS", "PKG_HOST_URL"))
end

-- Set app store server address
_M.set_pkg_host_url = function(value)
	dc.set("SYS", "PKG_HOST_URL", value)
end

-- Get config server address
_M.cnf_host_url = function()
	return _M.make_url(dc.get("SYS", "CNF_HOST_URL"))
end

-- Set config server address
_M.set_cnf_host_url = function(value)
	dc.set("SYS", "CNF_HOST_URL", value)
end

-- Get config auto upload option (not functional yet)
_M.cfg_auto_upload = function()
	return dc.get('SYS', "CFG_AUTO_UPLOAD")
end

-- Set config auto upload option (1 or 0)
_M.set_cfg_auto_upload = function(value)
	dc.set('SYS', 'CFG_AUTO_UPLOAD', value)
end

-- Get whether FreeIOE is running in developer mode
_M.developer_mode = function()
	return os.getenv("IOE_DEVELOPER_MODE") or dc.get('SYS', 'DEVELOPER_MODE')
end

-- Get cloud connection status
_M.cloud_status = function()
	local cloud = snax.uniqueservice("cloud")
	local online, last, msg = cloud.req.get_status()
	return online, last, msg
end

-- Return time in ms sine FreeIOE start
_M.now = function()
	return skynet.now() * 10 --- ms
end

-- Return time in seconds, decimal value is ms
_M.time = skynet.time
-- Return FreeIOE start time in UTC (in seconds, decimal value is ms)
_M.starttime = skynet.starttime
-- Return time in ns
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

-- Abort FreeIOE run, timeout in ms
_M.abort = function(timeout)
	local timeout = timeout or 5000
	skynet.timeout(100, function()
		skynet.call(".cfg", "lua", "save")
		skynet.call(".upgrader", "lua", "system_quit", 'ioe.abort', {delay=timeout})
	end)
end

-- FreeIOE enviroment
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
