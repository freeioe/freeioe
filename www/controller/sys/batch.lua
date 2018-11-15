local snax = require 'skynet.snax'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		local get = ngx.req.get_uri_args()

		local cloud = snax.queryservice('cloud')
		local result, info = cloud.req.batch_result(get.id)

		lwf.json(self, {result=result, info=info})
	end,
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.id and post.script)

		local cloud = snax.queryservice('cloud')
		cloud.post.batch_script(post.id, post.script)
		ngx.print(_('Script is running!'))
	end,
}
