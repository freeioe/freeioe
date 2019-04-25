local cjson = require 'cjson.safe'
local log_reader = require 'utils.log_reader'

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			return
		end
		local get = ngx.req.get_uri_args()
		local typ = get['type']
		local max_line = get.max_line or 64

		local s = nil
		if typ == 'dmesg' then
			s = log_reader.dmesg()
		else
			s = log_reader.by_type(typ, max_line)
		end
		local accept_json = string.match(ngx.var.header.accept, 'application/json')
		if s and accept_json and typ ~= 'dmesg' then
			ngx.header.content_type = "application/json; charset=utf-8"
			local logs = log_reader.parse_log(s)
			ngx.print(cjson.encode(logs))
		else
			ngx.header.content_type = "text/plain; charset=utf-8"
			ngx.print(s)
		end
	end,
}
