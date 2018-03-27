local snax = require 'skynet.snax'
local cjson = require 'cjson.safe'
local log_reader = require 'log_reader'

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local app = get['app']
		local max_line = get.max_line or 256

		local logs = {}
		local err = nil
		if get.from_file then
			logs, err = log_reader.by_app(app, max_line)
		else
			local buffer = snax.uniqueservice("buffer")
			logs, err = buffer.req.get_log(app)
			for _, log in ipairs(logs) do
				log.time = os.date("%D %T ", math.floor(log.timestamp)) .. math.floor((log.timestamp % 1) * 1000)
			end
		end

		local accept_json = string.match(ngx.var.header.accept, 'application/json')
		if logs then
			ngx.header.content_type = "application/json; charset=utf-8"
			ngx.print(cjson.encode(logs))
		else
			ngx.print(err)
		end
	end,
}
