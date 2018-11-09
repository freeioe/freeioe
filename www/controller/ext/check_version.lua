local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local inst = get.inst
		local ext = get.ext
		local version = get.version

		local tp, err = skynet.call(".ioe_ext", "lua", "pkg_check_version", ext, version)
		local ret = {}
		if tp then
			ret['type'] = tp
		else
			ret.message = err
		end
		lwf.json(self, ret)
	end,
}
