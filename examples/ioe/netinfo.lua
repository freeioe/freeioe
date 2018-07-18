local _M = {}

function _M.proc_net_dev(ifname)
	local f, err = io.open("/proc/net/dev")
	if not f then
		return nil, err
	end

	for line in f:lines() do
		--print('LINE', line)
		local ifn, info = string.match(line, '^%s*(.+):%s*(.+)$')
		if ifn and ifn == ifname and info then
			local t = {}
			for d in string.gmatch(info, '(%d+)') do
				t[#t + 1] = tonumber(d)
			end
			return t
		end
	end
	f:close()

	return nil, ifname.." not found in /proc/net/dev"
end

return _M
