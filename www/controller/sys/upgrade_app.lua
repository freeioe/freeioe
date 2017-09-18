local skynet = require 'skynet'

return {
	post = function(self)
		local post = ngx.req.get_post_args()
		local inst = post.inst
		local app = post.app
		local version = post.version
		local id = "from_web"
		local args = {
			version = version,
			inst = inst,
			name = app,
		}
		skynet.call("UPGRADER", "lua", "upgrade_app", id, args)
		ngx.print('Application upgrade is done!')
	end,
}
