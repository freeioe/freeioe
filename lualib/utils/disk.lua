local si = require 'utils.sysinfo'

local _M = {}

function _M.df(path)
	local path = path or '/'
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
	--print(patt)

	local r = {}
	for line in lines do
		local fs, t, total, used, aval, perc, mount = line:match(patt)
		if fs and string.lower(fs) ~= 'filesystem' then
			--print(fs, t, total, used, aval, perc, mount)
			r[#r + 1] = {
				filesystem = fs,
				['type'] = t,
				total = tonumber(total),
				used = tonumber(used),
				avaliable = tonumber(aval),
				used_percent = tonumber(perc),
				mount_on = mount,
			}
		end
	end
	if #r == 1 then
		return r[1]
	end
	return r
end

return _M
