local skynet = require 'skynet'
local dc = require 'skynet.datacenter'
local sysinfo = require 'utils.sysinfo'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local version = get.version
		local skynet_version = get.skynet_version
		local plat = sysinfo.platform()

		local ioe_data, err = skynet.call(".upgrader", "lua", "check_version", "freeioe", version, true)
		local skynet_data, err = skynet.call(".upgrader", "lua", "check_version", "skynet", skynet_version, true)
		
		lwf.json(self, {
			ioe = ioe_data.beta and 'beta' or 'release',
			skynet = skynet_data and 'beta' or 'release'
		})
	end,
}
