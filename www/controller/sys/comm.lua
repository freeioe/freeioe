local snax = require 'skynet.snax'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local commlog = snax.uniqueservice('commlog')
		local list = commlog.req.get(get.app)
		lwf.json(self, list)
	end,
}
