local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local inst = get.inst
		local version = get.version
		local app = dc.get('APPS', inst)
		assert(app and app.name==get.app)

		if app.islocal then
			lwf.json(self, {
				['type'] = 'local'
			})
			return
		end

		local tp, err = skynet.call(".upgrader", "lua", "pkg_check_version", app.name, app.version)
		local ret = {}
		if tp then
			ret['type'] = tp
		else
			ret.message = err
		end
		lwf.json(self, ret)
	end,
}
