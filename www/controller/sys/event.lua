local snax = require 'skynet.snax'
local cjson = require 'cjson.safe'
local log_reader = require 'utils.log_reader'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			return
		end
		local get = ngx.req.get_uri_args()
		local app = get['app']

		local buffer = snax.queryservice("buffer")
		local list, err = buffer.req.get_event()
		for _, v in ipairs(list or {}) do
			local ms = string.format("%03d", math.floor((v.timestamp % 1) * 1000))
			--v.time = os.date("%D %T "..ms, math.floor(v.timestamp))
			v.time = os.date("%D %H:%M:%S "..ms, math.floor(v.timestamp))
		end
		if app then
			local ol = list
			local list = {}
			for _, v in ipairs(list or {}) do
				if v.app == app then
					list[#list + 1] = v
				end
			end
		end

		lwf.json(self, list or "[]")
	end,
}
