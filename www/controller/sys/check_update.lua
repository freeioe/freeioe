local skynet = require 'skynet'
local sysinfo = require 'utils.sysinfo'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local beta = (get.beta == 'true' and true or false)
		local iot_ver, iot_beta = skynet.call("UPGRADER", "lua", "pkg_check_update", "skynet_iot", beta)
		assert(iot_ver)

		local plat = sysinfo.skynet_platform()
		local sver, sbeta = skynet.call("UPGRADER", "lua", "pkg_check_update", plat.."_skynet", beta)
		assert(sver)
		local ret = {
			iot = {
				version = iot_ver,
				beta = iot_beta
			},
			skynet = {
				version = sver,
				beta = sbeta,
			}
		}

		lwf.json(self, ret)
	end,
}
