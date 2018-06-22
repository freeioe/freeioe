local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end
		local using_beta = dc.get('CLOUD', 'USING_BETA')
		if not using_beta then
			ngx.print(_('FreeIOE device in not in beta mode!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local inst = post.inst
		local app = post.app
		assert(inst and app)
		if string.len(inst) < 3 or string.len(app) < 3 then
			ngx.print("Application name or inst cannot be empty!")
			return
		end

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
