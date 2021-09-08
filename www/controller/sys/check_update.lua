local skynet = require 'skynet'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local ioe_data = skynet.call(".upgrader", "lua", "latest_version", "freeioe", true)
		assert(ioe_data)

		local skynet_data = skynet.call(".upgrader", "lua", "latest_version", "skynet", true)
		assert(skynet_data)
		local ret = {
			ioe = ioe_data,
			skynet = skynet_data,
		}

		lwf.json(self, ret)
	end,
}
