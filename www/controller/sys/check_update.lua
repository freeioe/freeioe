local skynet = require 'skynet'
local sysinfo = require 'utils.sysinfo'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local beta = (get.beta == 'true' and true or false)
		local version, beta = skynet.call("UPGRADER", "lua", "pkg_check_update", "skynet_iot", beta)
		assert(version)

		local plat = sysinfo.skynet_platform()
		local sver, sbeta = skynet.call("UPGRADER", "lua", "pkg_check_update", plat.."_skynet", beta)
		assert(sver)
		local ret = {
			iot = {
				version = version,
				beta = beta
			},
			skynet = {
				version = sver,
				beta = sbeta,
			}
		}

		lwf.json(self, ret)
	end,
}
