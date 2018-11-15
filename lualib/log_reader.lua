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

local function filter_log_file(file, max_line, s_match)
	local dir = lfs.currentdir()
	local cmd = 'tail -n '..max_line..' '..dir..'/logs/'..file
	local f, err = io.popen(cmd)
	if not f then
		return {}
	end

	local l = {}
	for line in f:lines() do
		if string.match(line, s_match) then
			l[#l + 1] = line
			--print(line)
		end
	end
	return l
end

-- Return {log={...}, sys={...}}
function _M.by_app(app_name, count)
	local appmgr = snax.queryservice("appmgr")
	local app_inst, err = appmgr.req.app_inst(app_name)
	if not app_inst then
		return nil, err
	end

	local log_inst = string.format("%08x", app_inst.handle)
	local filter = "%["..log_inst.."%]"

	local sys_log = filter_log_file('freeioe_sys.log', count, filter)
	local log = filter_log_file('freeioe.log', count, filter)

	return {
		sys = sys_log,
		log = log
	}

	--[[
	for _, l in ipairs(log) do
		sys_log[#sys_log + 1] = l
	end
	return table.concat(sys_log, '\n')
	]]--
end

-- Return plain text log
function _M.by_type(typ, count)
	local s = nil
	if typ == 'sys' then
		s = tail_log_file('freeioe_sys.log', count)
	else
		s = tail_log_file('freeioe.log', count)
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
