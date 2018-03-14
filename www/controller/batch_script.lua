local snax = require 'skynet.snax'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		lwf.render('batch_script.html')
	end,
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.id and post.script)

		local cloud = snax.uniqueservice('cloud')
		cloud.post.batch_script(post.id, post.script)
		ngx.print(_('Script is running!'))
	end,
}
