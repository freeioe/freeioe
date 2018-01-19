local cjson = require 'cjson.safe'
local log_reader = require 'log_reader'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local app = get['app']
		local max_line = get.max_line or 64

		local s, err = log_reader.by_app(app, max_line)
		local accept_json = string.match(ngx.var.header.accept, 'application/json')
		if s and accept_json and typ ~= 'dmesg' then
			ngx.header.content_type = "application/json; charset=utf-8"
			local logs = log_reader.parse_log(s)
			ngx.print(cjson.encode(logs))
		else
			ngx.header.content_type = "text/plain; charset=utf-8"
			ngx.print(s or err)
		end
	end,
}
