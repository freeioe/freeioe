local snax = require 'skynet.snax'

return {
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.inst)
		local appmgr = snax.uniqueservice('appmgr')
		local r, err = appmgr.req.start(post.inst)
		if r then
			ngx.print(_('Application started!'))
		else
			ngx.print(err)
		end
	end,
}
