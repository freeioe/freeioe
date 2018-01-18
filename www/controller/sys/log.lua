local cjson = require 'cjson.safe'
local log_finder = require 'log_finder'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local typ = get['type']
		local max_line = get.max_line or 64

		local s = nil
		if typ == 'dmesg' then
			s = log_finder.dmesg()
		else
			s = log_finder.by_type(typ, max_line)
		end
		local accept_json = string.match(ngx.var.header.accept, 'application/json')
		if s and accept_json and typ ~= 'dmesg' then
			ngx.header.content_type = "application/json; charset=utf-8"
			local logs = log_finder.parse_log(s)
			ngx.print(cjson.encode(logs))
		else
			ngx.header.content_type = "text/plain; charset=utf-8"
			ngx.print(s)
		end
	end,
}
