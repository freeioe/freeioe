local sysinfo = require 'utils.sysinfo'

local _M  = {}

local html_escape_entities = {
	['&'] = '&amp;',
	['<'] = '&lt;',
	['>'] = '&gt;',
	['"'] = '&quot;',
	["'"] = '&#039;'
}

function _M.escape(text)
	text = text or ""
	return (text:gsub([=[["><'&]]=], html_escape_entities))
end

function _M.encode_query_string (t, sep)
	local escape = _M.escape
	local sep = sep or "&"
	local i = 0
	local buf = { }
	for k, v in pairs(t) do
		if type(k) == "number" and type(v) == "table" then
			k, v = v[1], v[2]
		end
		buf[i + 1] = escape(k)
		buf[i + 2] = "="
		buf[i + 3] = escape(tostring(v))
		buf[i + 4] = sep
		i = i + 4
	end
	buf[i] = nil
	return table.concat(buf)
end

_M.md5sum_lua = function(file_path)
	local md5 = require 'hashings.md5'()
	local f, err = io.open(file_path, "r")
	if not f then
		return nil, err
	end
	while true do
		local s = f:read(4096)
		if not s then
			break
		end
		md5:update(s)
	end
	f:close()
	return md5:hexdigest()
end

local function check_exists(exec)
	local lfs = require 'lfs'
	local plat = sysinfo.platform()
	assert(plat, "OS Platform is nil")
	assert(lfs.currentdir(), "LFS CurrentDir is nil")
	local path = lfs.currentdir().."/ioe/linux/"..plat.."/"..exec
	local f, err = io.open(path, "r")
	if f then
		f:close()
		return path
	end
	return nil, err
end

_M.md5sum = function(file_path)
	local md5sum_exe = check_exists('md5sum') or 'md5sum'
	local f, err = io.popen(md5sum_exe..' '..file_path)
	if not f then
		return nil, err
	end
	local s = f:read('*a')
	f:close()
	return s:match('^(%w+)[^%w]+(%g+)')
end

return _M
