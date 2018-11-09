local dc = require 'skynet.datacenter'
local skynet = require 'skynet'
local ioe = require 'ioe'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		else
			local exts = skynet.call(".ioe_ext", "lua", "list")
			local pkg_host_url = ioe.pkg_host_url()
			local using_beta = ioe.beta()
			lwf.render('ext.html', {exts=exts, pkg_host_url=pkg_host_url, force_upgrade=get.force_upgrade, using_beta=using_beta})
		end
	end
}
