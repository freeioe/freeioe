local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local inst = get.inst
		local ext = get.ext
		local data = skynet.call(".ioe_ext", "lua", "latest_version", ext)
		lwf.json(self, {version=data.version, beta=data.beta})
	end,
}
