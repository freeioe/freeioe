local skynet = require 'skynet'
local sysinfo = require 'utils.sysinfo'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local beta = (get.beta == 'true' and true or false)
		local ioe_ver, ioe_beta = skynet.call(".upgrader", "lua", "pkg_check_update", "freeioe", beta)
		assert(ioe_ver)

		local plat = sysinfo.platform()
		local sver, sbeta = skynet.call(".upgrader", "lua", "pkg_check_update", plat.."_skynet", beta)
		assert(sver)
		local ret = {
			ioe = {
				version = ioe_ver,
				beta = ioe_beta
			},
			skynet = {
				version = sver,
				beta = sbeta,
			}
		}

		lwf.json(self, ret)
	end,
}
