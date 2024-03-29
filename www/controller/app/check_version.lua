local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local inst = get.inst
		local version = get.version
		local app = dc.get('APPS', inst)
		assert(app and app.name)

		if app.islocal then
			lwf.json(self, {
				['type'] = 'local'
			})
			return
		end

		local tp, err = skynet.call(".upgrader", "lua", "check_version", app.name, app.version, false)
		local ret = {}
		if tp then
			ret['type'] = tp.beta and 'beta' or 'release'
		else
			ret.message = err
		end
		lwf.json(self, ret)
	end,
}
