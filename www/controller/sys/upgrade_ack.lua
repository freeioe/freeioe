local skynet = require 'skynet'

return {
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local id = "from_web"
		local args = {
			from_web = true
		}
		skynet.call("UPGRADER", "lua", "upgrade_core_ack", id, args)
		ngx.print('System upgrade ack is done!')
	end,
}
