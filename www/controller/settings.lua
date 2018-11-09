local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local ioe = require 'ioe'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
		else
			local get = ngx.req.get_uri_args()
			local using_beta = ioe.beta()
			local pkg_host = ioe.pkg_host_url()
			local cnf_host = ioe.cnf_host_url()
			local cfg_upload = ioe.cfg_auto_upload()
			lwf.render('settings.html', {
				using_beta=using_beta,
				pkg_host=pkg_host,
				cnf_host=cnf_host,
				cfg_upload=cfg_upload,
				edit_enable=get.edit_enable
			})
		end
	end,
	post = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local action = post.action
		if action == 'pkg' then
			local option = post.option
			local value = post.value
			if value == 'true' then value = true end
			if value == 'false' then value = false end
			if value and option == 'using_beta' then
				local r, err = skynet.call(".upgrader", "lua", "pkg_enable_beta")
				if not r then
					ngx.print(string.format(_('Cannot enable beta. Error: %s'), err))
					return
				end
				value = r
			end
			dc.set('SYS', string.upper(option), value)
			ngx.print(_('PKG option is changed!'))
		end
	end
}
