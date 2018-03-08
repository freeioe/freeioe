local skynet = require 'skynet'
local snax = require 'skynet.snax'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local inst = post.inst
		local app = post.app
		assert(inst and app)

		local id = "from_web"
		local args = {
			name = app,
			inst = inst,
			from_web = true,
		}
		local r, err = skynet.call("UPGRADER", "lua", "create_app", id, args)
		if r then
			ngx.print('Application creation is done!')
			local cloud = snax.uniqueservice('cloud')
			if cloud then
				cloud.post.fire_apps()
			end
		else
			ngx.print('Application creation failed', err)
		end
	end,
}
