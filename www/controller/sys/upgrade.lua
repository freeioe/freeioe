local skynet = require 'skynet'

return {
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local version = post.version
		local id = "from_web"
		local args = {
			no_ack = 1,
			skynet = {
				platform = "openwrt",
			},
		}
		skynet.call("UPGRADER", "lua", "upgrade_core", id, args)
		ngx.print('System upgrade is done!')
	end,
}
