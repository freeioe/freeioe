local snax = require 'skynet.snax'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.inst and post.new_name)
		assert(string.len(post.inst) > 0)
		assert(string.len(post.new_name) > 0)

		local appmgr = snax.queryservice('appmgr')
		local r, err = appmgr.req.app_rename(post.inst, post.new_name)
		if not r then
			ngx.print(_(err))
		else
			ngx.print(_('Application option changed!'))
		end
	end,
}
