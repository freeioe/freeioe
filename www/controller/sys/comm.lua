local snax = require 'skynet.snax'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local buffer = snax.uniqueservice('buffer')
		local list = buffer.req.get_comm(get.app) or "[]"
		lwf.json(self, list)
	end,
}
