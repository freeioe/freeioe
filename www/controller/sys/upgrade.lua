local skynet = require 'skynet'

return {
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local version = post.version
		local id = "from_web"

		local no_ack = post.no_ack and post.no_ack == 'true' or false
		local args = {
			no_ack = no_ack,
			version = version,
		}

		local up_skynet = post.skynet and post.skynet == 'true' or false
		if up_skynet then
			args.skynet = {
				version = post.skynet_version
			}
		end

		skynet.call("UPGRADER", "lua", "upgrade_core", id, args)
		ngx.print(_('System upgrade is done! System will be offline for a few seconds!'))
	end,
}
