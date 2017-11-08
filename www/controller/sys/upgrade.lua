local skynet = require 'skynet'

return {
	post = function(self)
		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local version = post.version
		local id = "from_web"

		local args = {
			no_ack = post.skip_ack,
			version = version,
		}

		local with_skynet = post.with_skynet
		if with_skynet then
			args.skynet = {
				version = post.skynet_version
			}
		end

		skynet.call("UPGRADER", "lua", "upgrade_core", id, args)
		ngx.print(_('System upgrade is done! System will be offline for a few seconds!'))
	end,
}
