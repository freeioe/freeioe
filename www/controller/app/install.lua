local skynet = require 'skynet'
local snax = require 'skynet.snax'

return {
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local cjson = require 'cjson'
		local inst = post.inst
		local app = post.app
		local version = post.version or 'latest'
		assert(inst and app)

		local conf = post.conf
		if type(conf) == 'string' then
			conf = cjson.decode(conf)
		end

		local id = "from_web"
		local args = {
			name = app,
			inst = inst,
			version = version,
			from_web = true,
			conf = conf,
		}
		local r, err = skynet.call("UPGRADER", "lua", "install_app", id, args)
		if r then
			ngx.print('Application uninstall is done!')
			local cloud = snax.uniqueservice('cloud')
			if cloud then
				cloud.post.fire_apps()
			end
		else
			ngx.print('Application uninstall failed', err)
		end
	end,
}
