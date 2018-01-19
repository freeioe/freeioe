local cjson = require 'cjson.safe'
local log_reader = require 'log_reader'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local app = get['app']
		local max_line = get.max_line or 256

		local log, err = log_reader.by_app(app, max_line)
		local accept_json = string.match(ngx.var.header.accept, 'application/json')
		if log and accept_json and typ ~= 'dmesg' then
			ngx.header.content_type = "application/json; charset=utf-8"
			ngx.print(cjson.encode(log))
		else
			local s = nil
			if log then
				s = table.concat(log.sys, '\n')
				s = s..'\n========================================================\n'
				s = s..table.concat(log.log, '\n')
			end
			ngx.header.content_type = "text/plain; charset=utf-8"
			ngx.print(s or err)
		end
	end,
}
