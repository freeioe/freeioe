local lfs = require 'lfs'
local cjson = require 'cjson.safe'

local function parse_log(s)
	local logs = {}
	for line in string.gmatch(s, "[^\n]+") do
		local time, level, process, content = string.match(line, '^(%g+ %g+) %[(.+)%] %[(.+)%]: (.+)$')
		logs[#logs + 1] = {
			time = time,
			level = level,
			process = process,
			content = content
		}
	end
	return logs
end

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

		local s = nil
		if typ == 'sys' then
			s = tail_log_file('skynet_sys.log', max_line)
		elseif typ == 'dmesg' then
			s = dmesg_log()
		else
			s = tail_log_file('skynet.log', max_line)
		end
		local accept_json = string.match(ngx.var.header.accept, 'application/json')
		if s and accept_json and typ ~= 'dmesg' then
			ngx.header.content_type = "application/json; charset=utf-8"
			local logs = parse_log(s)
			ngx.print(cjson.encode(logs))
		else
			ngx.header.content_type = "text/plain; charset=utf-8"
			ngx.print(s)
		end
	end,
}
