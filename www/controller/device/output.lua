local snax = require 'skynet.snax'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.device and post.output and post.value)

		local cloud = snax.queryservice('cloud')
		local info = {
			device = post.device,
			output = post.output,
			value = post.value
		}
		cloud.post.output_to_device(post.id or "FromWeb-"..lwf.auth.user, info)
		ngx.print(_('Device output fired!'))
	end,
}
