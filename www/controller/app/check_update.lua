local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local inst = get.inst
		local app = dc.get('APPS', inst)
		assert(app and app.name==get.app)
		local version, beta = skynet.call("UPGRADER", "lua", "pkg_check_update", app.name, true)
		lwf.json(self, {version=version, beta=beta})
	end,
}
