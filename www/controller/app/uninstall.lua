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
		local cjson = require 'cjson'
		local inst = post.inst
		assert(inst)

		local id = "from_web"
		local args = {
			inst = inst,
			from_web = true
		}
		local r, err = skynet.call("UPGRADER", "lua", "uninstall_app", id, args)
		if r then
			ngx.print('Application uninstall is done!')
			local cloud = snax.uniqueservice('cloud')
			if cloud then
				cloud.post.fire_apps(100)
			end
		else
			ngx.print('Application uninstall failed', err)
		end
	end,
}
