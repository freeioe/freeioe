local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local inst = get.inst
		local app = dc.get('APPS', inst)
		if app.islocal then
			lwf.json(self, {version=app.version})
			return
		end
		assert(app and app.name==get.app)
		local data = skynet.call(".upgrader", "lua", "latest_version", app.name, false)
		lwf.json(self, {version=data.version, beta=data.beta})
	end,
}
