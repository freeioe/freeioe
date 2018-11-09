local skynet = require 'skynet'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local action = post.action
		local from_web = post.from_web
		local id = "from_web"

		if action == 'reboot' then
			local args = { from_web = from_web, delay = 5 }
			skynet.call(".upgrader", "lua", "system_reboot", id, args)
			ngx.print(_('Device will be reboot after five seconds!'))
		end
		if action == 'quit' then
			local args = { from_web = from_web, delay = 5 }
			skynet.call(".upgrader", "lua", "system_quit", id, args)
			ngx.print(_('System will be restart after five seconds!'))
		end
		if action == 'upgrade_ack' then
			local args = { from_web = from_web }
			skynet.call(".upgrader", "lua", "upgrade_core_ack", id, args)
			ngx.print(_('System upgrade ack is done!'))
		end
	end,
}
