local snax = require 'skynet.snax'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			return
		end
		local get = ngx.req.get_uri_args()
		local buffer = snax.queryservice('buffer')
		local list = buffer.req.get_comm(get.app) or "[]"
		lwf.json(self, list)
	end,
}
