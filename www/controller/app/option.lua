local snax = require 'skynet.snax'

local options = {
	once = 1
}

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.inst and post.option)
		if not options[post.option] then
			ngx.print(_("Option is invalid!"))
			return
		end

		local appmgr = snax.uniqueservice('appmgr')
		local r, err = appmgr.post.app_option(post.inst, post.option, post.value)
		if r then
			ngx.print(_('Application option changed!'))
		else
			ngx.print(err)
		end
	end,
}
