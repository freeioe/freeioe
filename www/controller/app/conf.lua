local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local cjson = require 'cjson.safe'

return {
	get= function(self)
		if lwf.auth.user == 'Guest' then
			return
		end
		local get = ngx.req.get_uri_args()
		local app = get.inst
		if not app then
			return
		end

		local appmgr = snax.queryservice('appmgr')
		local conf = appmgr.req.get_conf(app)
		lwf.json(self, conf)
	end,
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.inst and post.conf)
		assert(string.len(post.inst) > 0)

		if type(post.conf) ~= 'table' then
			if string.len(post.conf) > 0 then
				post.conf = cjson.decode(post.conf) or {}
			else
				post.conf = {}
			end
		end
		local appmgr = snax.queryservice('appmgr')
		local r, err = appmgr.req.set_conf(post.inst, post.conf)
		if r then
			ngx.print(_('Application configuration changed!'))
		else
			ngx.print(_(err))
		end
	end,
}
