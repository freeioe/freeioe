local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local inst = get.inst
		local ext = get.ext
		local version, beta = skynet.call(".ioe_ext", "lua", "pkg_check_update", ext, true)
		lwf.json(self, {version=version, beta=beta})
	end,
}
