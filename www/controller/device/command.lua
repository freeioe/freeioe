local snax = require 'skynet.snax'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.device and post.command and post.param)

		local cloud = snax.queryservice('cloud')
		local cmd = {
			device = post.device,
			cmd = post.command,
			param = post.param
		}
		cloud.post.command_to_device(post.id or "FromWeb-"..lwf.auth.user, cmd)
		ngx.print(_('Device command fired!'))
	end,
}
