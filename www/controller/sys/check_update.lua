local skynet = require 'skynet'
local sysinfo = require 'utils.sysinfo'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local beta = (get.beta == 'true' and true or false)
		local ver, bver = skynet.call("UPGRADER", "lua", "pkg_check_update", "skynet_iot", beta)
		local version = beta and math.max(bver or 0, ver or 0) or ver 

		local plat = sysinfo.skynet_platform()
		local ver, bver = skynet.call("UPGRADER", "lua", "pkg_check_update", plat.."_skynet", beta)
		local sver = beta and math.max(bver or 0, ver or 0) or ver 

		lwf.json(self, {version=version, skynet=sver})
	end,
}
