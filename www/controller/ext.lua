local dc = require 'skynet.datacenter'
local skynet = require 'skynet'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		else
			local exts = skynet.call("IOT_EXT", "lua", "list")
			local pkg_host_url = dc.get('PKG_HOST_URL')
			local using_beta = dc.get('CLOUD', 'USING_BETA')
			lwf.render('ext.html', {exts=exts, pkg_host_url=pkg_host_url, force_upgrade=get.force_upgrade, using_beta=using_beta})
		end
	end
}
