local si = require 'utils.sysinfo'

local _M = {}

-- 验证路径安全性
local function validate_path(path)
	if not path or type(path) ~= 'string' then
		return nil, "Invalid path type"
	end
	-- 拒绝路径遍历
	if string.match(path, '%.%.') then
		return nil, "Path traversal not allowed"
	end
	-- 拒绝特殊字符
	if string.match(path, '[;|&$`%c]') then
		return nil, "Invalid characters in path"
	end
	return true
end

function _M.df(path)
	local path = path or '/'
	local ok, err = validate_path(path)
	if not ok then
		return nil, err
	end
	local cmd = 'LANG=C df -T '..path
	local s, err = si.exec(cmd)
	if not s then
		return nil, err
	end
	if string.len(s) == 0 then
		return nil, 'Failed to execute df command'
	end
	local lines = s:gmatch('(.-)\n')

	local sp = '%g'
	if _VERSION == 'Lua 5.1' then
		sp = '[^%s]'
	end

	local patt = '^('..sp..'+)%s-('..sp..'+)%s-(%d+)%s-(%d+)%s-(%d+)%s-(%d+)%%%s-('..sp..'+)$'

	local r = {}
	for line in lines do
		local fs, t, total, used, aval, perc, mount = line:match(patt)
		if fs and string.lower(fs) ~= 'filesystem' then
			r[#r + 1] = {
				filesystem = fs,
				['type'] = t,
				total = tonumber(total),
				used = tonumber(used),
				available = tonumber(aval),
				used_percent = tonumber(perc),
				mount_on = mount,
			}
		end
	end
	if #r == 1 then
		return r[1]
	end
	return nil, 'Failed to reading filesystem information on path:'..path
end

return _M
