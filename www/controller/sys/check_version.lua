local skynet = require 'skynet'
local dc = require 'skynet.datacenter'
local sysinfo = require 'utils.sysinfo'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local version = get.version
		local skynet_version = get.skynet_version
		local plat = sysinfo.skynet_platform()

		local iot_type, err = skynet.call("UPGRADER", "lua", "pkg_check_version", "skynet_iot", version)
		local skynet_type, err = skynet.call("UPGRADER", "lua", "pkg_check_version", plat.."_skynet", skynet_version)
		
		lwf.json(self, {iot=iot_type, skynet=skynet_type})
	end,
}
