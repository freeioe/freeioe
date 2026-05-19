local sysinfo = require 'utils.sysinfo'
local lfs = require 'lfs'

local _M  = {}

-- 验证文件路径安全性
local function validate_file_path(file_path)
	if not file_path or type(file_path) ~= 'string' then
		return nil, "Invalid file path type"
	end
	-- 拒绝路径遍历
	if string.match(file_path, '%.%.') then
		return nil, "Path traversal not allowed"
	end
	-- 拒绝shell元字符
	if string.match(file_path, '[;|&$`%c]') then
		return nil, "Invalid characters in file path"
	end
	return true
end

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
			buf[i + 1] = escape(v[1])
			buf[i + 2] = "="
			buf[i + 3] = escape(tostring(v[2]))
		else
			buf[i + 1] = escape(k)
			buf[i + 2] = "="
			buf[i + 3] = escape(tostring(v))
		end
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
	local ioe = require 'ioe'
	local arch = sysinfo.platform()
	assert(arch, "OS Arch is nil")

	local path = ioe.dir(true).."/linux/"..arch.."/"..exec

	local m, err = lfs.attributes(path, "mode")
	if m then
		return path
	end
	return nil, err
end

_M.md5sum = function(file_path)
	local ok, err = validate_file_path(file_path)
	if not ok then
		return nil, err
	end
	local md5sum_exe = check_exists('md5sum') or 'md5sum'
	local f, err = io.popen(md5sum_exe..' "'..file_path..'"')
	if not f then
		return nil, err
	end
	local s = f:read('*a')
	f:close()
	return s:match('^(%w+)[^%w]+(%g+)')
end

return _M
