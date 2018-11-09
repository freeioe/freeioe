local skynet = require 'skynet'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local cjson = require 'cjson'
		local inst = post.inst
		local app = post.app
		local version = post.version

		assert(inst and app)
		assert(string.len(inst) > 0)
		assert(string.len(app) > 0)

		local id = "from_web"
		local args = {
			version = version,
			inst = inst,
			name = app,
		}
		skynet.call(".upgrader", "lua", "upgrade_app", id, args)
		ngx.print('Application upgrade is done!')
	end,
}
