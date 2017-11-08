local dc = require 'skynet.datacenter'
local snax = require 'skynet.snax'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		else
			local using_beta = dc.get('CLOUD', 'USING_BETA')
			if not using_beta then
				self:redirect('/app')
				return
			end
			local get = ngx.req.get_uri_args()
			local inst = get.app
			local app = dc.get('APPS', inst) or {}
			local appmgr = snax.uniqueservice('appmgr')
			local applist = appmgr.req.list()
			app.running = applist[inst] and applist[inst].inst or nil
			app.version = math.floor(app.version)
			lwf.render('app_editor.html', {app=app})
		end
	end
}
