local dc = require 'skynet.datacenter'
local snax = require 'skynet.snax'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		else
			local apps = dc.get('APPS')
			local appmgr = snax.uniqueservice('appmgr')
			local applist = appmgr.req.list()
			for k, v in pairs(apps) do
				v.running = applist[k].inst
				v.version = math.floor(v.version)
			end
			local pkg_host_url = dc.get('PKG_HOST_URL')
			lwf.render('app.html', {apps=apps, pkg_host_url=pkg_host_url})
		end
	end
}
