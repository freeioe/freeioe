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
		assert(inst and string.len(inst) > 0)

		local id = "from_web"
		local args = {
			inst = inst,
			from_web = true
		}
		local r, err = skynet.call(".upgrader", "lua", "uninstall_app", id, args)
		if r then
			ngx.print('Application uninstall is done!')
		else
			ngx.print('Application uninstall failed', err)
		end
	end,
}
