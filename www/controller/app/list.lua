local dc = require 'skynet.datacenter'
local snax = require 'skynet.snax'
local ioe = require 'ioe'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		else
			local apps = dc.get('APPS') or {}
			local appmgr = snax.queryservice('appmgr')
			local applist = appmgr.req.list()
			for k, v in pairs(apps) do
				v.running = applist[k] and applist[k].inst or nil
				v.running = v.running and true or false
				v.version = math.floor(tonumber(v.version) or 0)
				v.auto = math.floor(tonumber(v.auto or 1))
			end
			local using_beta = ioe.beta() 
			lwf.json(self, {apps=apps, using_beta=using_beta})
		end
	end
}
