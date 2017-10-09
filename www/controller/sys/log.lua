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

local function dmesg_log()
	local f, err = io.popen('dmesg')
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
		local max_line = get.max_line or 64

		ngx.header.content_type = "text/plain; charset=utf-8"
		if typ == 'sys' then
			local s = tail_log_file('skynet_sys.log', max_line)
			return ngx.print(s)
		elseif typ == 'dmesg' then
			local s = dmesg_log()
			return ngx.print(s)
		else
			local s = tail_log_file('skynet.log', max_line)
			return ngx.print(s)
		end
	end,
}
