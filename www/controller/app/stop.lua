local snax = require 'skynet.snax'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.inst)
		local appmgr = snax.queryservice('appmgr')
		local r, err = appmgr.req.stop(post.inst, post.reason)
		if r then
			ngx.print(_('Application stoped!'))
		else
			ngx.print(err)
		end
	end,
}
