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
		local ext = post.ext
		local version = post.version
		assert(inst and ext)
		assert(string.len(inst) > 0)
		assert(string.len(ext) > 0)

		local id = "from_web"
		local args = {
			version = version,
			inst = inst,
			name = ext,
		}
		skynet.call(".ioe_ext", "lua", "upgrade_ext", id, args)
		ngx.print('Extension upgrade is done!')
	end,
}
