local lfs = require 'lfs'

local function tail_log_file(file, max_line)
	local dir = lfs.currentdir()
	local cmd = 'tail -n '..max_line..' '..dir..'/logs/'..file
	local f, err = io.popen(cmd)
	if not f then
		return {}
	end
	local s = f:read('a')
	f:close()
	return s
end

return {
	get = function(self)
		local get = ngx.req.get_uri_args()
		local typ = get['type']

		ngx.header.content_type = "text/plain; charset=utf-8"
		if typ == 'sys' then
			local s = tail_log_file('skynet_sys.log', 100)
			return ngx.print(s)
		else
			local s = tail_log_file('skynet.log', 100)
			return ngx.print(s)
		end
	end,
}
