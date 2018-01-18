local skynet = require 'skynet'
local snax = require 'skynet.snax'
local lfs = require 'lfs'
local cjson = require 'cjson.safe'

local _M = {}

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


function _M.by_app(app, count)
end

function _M.by_type(typ, count)
	local s = nil
	if typ == 'sys' then
		s = tail_log_file('skynet_sys.log', count)
	else
		s = tail_log_file('skynet.log', count)
	end
	return s
end

function _M.parse_log(s)
	return parse_log(s)
end

function _M.dmesg()
	local f, err = io.popen('dmesg')
	if not f then
		return {}
	end
	local s = f:read('a')
	f:close()
	return s
end

return _M
