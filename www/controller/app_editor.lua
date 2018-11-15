local dc = require 'skynet.datacenter'
local snax = require 'skynet.snax'
local ioe = require 'ioe'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		else
			local using_beta = ioe.beta()
			if not using_beta then
				self:redirect('/app')
				return
			end
			local get = ngx.req.get_uri_args()
			local inst = get.app
			local app = dc.get('APPS', inst) or {}
			local appmgr = snax.queryservice('appmgr')
			local applist = appmgr.req.list()
			app.running = applist[inst] and applist[inst].inst or nil
			app.version = math.floor(app.version or 0)
			app.inst = app.inst or inst
			lwf.render('app_editor.html', {app=app})
		end
	end
}
