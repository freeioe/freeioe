local dc = require 'skynet.datacenter'
local snax = require 'skynet.snax'
local cjson = require 'cjson'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		else
			local apps = dc.get('APPS') or {}
			local appmgr = snax.uniqueservice('appmgr')
			local applist = appmgr.req.list()
			for k, v in pairs(apps) do
				v.running = applist[k] and applist[k].inst or nil
				v.version = math.floor(v.version)
			end
			local pkg_host_url = dc.get('PKG_HOST_URL')
			local using_beta = dc.get('CLOUD', 'USING_BETA')
			lwf.render('app.html', {apps=apps, pkg_host_url=pkg_host_url, force_upgrade=get.force_upgrade, using_beta=using_beta})
		end
	end
}
