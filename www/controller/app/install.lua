local skynet = require 'skynet'
local snax = require 'skynet.snax'

local default_conf = {
	ioe_frpc = {
		auto_start = true,
		enable_web = true,
		token = "BWYJVj2HYhVtdGZL",
	},
}

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
		local version = post.version or 'latest'
		assert(inst and app)
		assert(string.len(inst) > 0 and string.len(app) > 0)

		local conf = post.conf or default_conf[inst] or {}
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
		local r, err = skynet.call(".upgrader", "lua", "install_app", id, args)
		if r then
			ngx.print('Application installation is done!')
		else
			ngx.print('Application installation failed', err)
		end
	end,
}
