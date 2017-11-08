--- Helper functions for getting system information
-- @author Dirk Chang
--

local _M = {}


--- Get output of shell command
--
_M.exec = function(cmd)
	local f, err = io.popen(cmd)
	if not f then
		return nil, err
	end
	local s = f:read('*a')
	f:close()
	return s
end

--- Get the cpu model
-- @treturn string CPU Model 
_M.cpu_model = function()
	local s, err = _M.exec('cat /proc/cpuinfo')
	--return s:match("Hardware%s+:%s+([^%c]+)")
	return s:match("model%s+name%s*:%s*([^%c]+)") or s:match("system%s+type%s*:%s*([^%c]+)") or 'Unknown'
end

--- Get the output for uname
-- @tparam string arg The args for uname command. e.g. -a -A -u
-- @treturn string the output from uname
_M.uname = function(arg)
	local cmd = 'uname '..arg
	local s, err = _M.exec(cmd)
	if not s then
		return nil, err
	end

	s = string.gsub(s, "\n", "")

	return s
end

local function proc_mem_info()
	local s, err = _M.exec('cat /proc/meminfo')
	if not s then
		return nil, err
	end

	local total = s:match("MemTotal:%s-(%d+)")
	local free = s:match("MemFree:%s-(%d+)")
	local used = total - free

	return {total = total, used = used, free=free}
end

--- Get the memory information
-- includes 'total' 'used' 'free'
-- @treturn table information struct {total=xx, used=xx, free=xx}
_M.meminfo = function()
	local s, err = _M.exec('free')
	if not s then
		return nil, err
	end

	local info = s:gmatch("Mem:%s-(%d+)%s-(%d+)%s-(%d+)")
	local total, used, free = info()
	if total then
		return { total = total, used = used, free = free }
	else
		return proc_mem_info()
	end
end

--- Get he loadavg
-- output the loadavg as one table, includes: lavg_1, lavg_5, lavg_15, nr_running, nr_threads, last_pid
-- @treturn table Refer to description
_M.loadavg = function()
	local s, err = _M.exec('cat /proc/loadavg')
	if not s then
		return nil, err
	end

	-- Find the idle times in the stdout output
	local tokens = s:gmatch('%s-([%d%.]+)')

	local avgs = {}
	for w in tokens do
		avgs[#avgs + 1] = w
	end
	local unpack = table.unpack or unpack
	local lavg_1, lavg_5, lavg_15, nr_running, nr_threads, last_pid = unpack(avgs)
	return {
		lavg_1 = lavg_1,
		lavg_5 = lavg_5,
		lavg_15 = lavg_15,
		nr_running = nr_running,
		nr_threads = nr_threads,
		last_pid = last_pid
	}
end

--- Get the network information
-- @tparam string ifname The interface name
-- @treturn table
local function network_if(ifname)
	local patt = '%g'
	if _VERSION == 'Lua 5.1' then
		patt = '[^%s]'
	end

	local s, err = _M.exec('LANG=C ifconfig '..ifname)
	if not s then
		return nil, err
	end

	local hwaddr = s:match('HWaddr%s-('..patt..'+)')
	local ipv4 = s:match('inet%s+addr:%s-('..patt..'+)')
	local ipv6 = s:match('inet6%s+addr:%s-('..patt..'+)')
	return {hwaddr=hwaddr, ipv4 = ipv4, ipv6=ipv6}
end

--- List all network interfaces
-- @treturn table Includes all network information
_M.network = function()
	local patt = '[%g^:]'
	if _VERSION == 'Lua 5.1' then
		patt = '[^%s:]'
	end

	local s, err = _M.exec('cat /proc/net/dev')
	if not s then
		return nil, err
	end

	local tokens = s:gmatch('%s-('..patt..'+):')
	local ifs = {}
	for w in tokens do
		if w ~= 'lo' then
			ifs[#ifs + 1] = w
		end
	end
	local info = {}
	for k, v in pairs(ifs) do
		info[v] = network_if(v)
	end
	return info;
end

_M.list_serial = function()
	local f = io.popen('ls /dev/ttyS* /dev/ttyUSB* /dev/ttyACM*')
	if not f then
		return nil, err
	end

	local list = {}
	for line in f:lines() do
		local name = line:match('^(/dev/tty.+)$')
		list[#list + 1] = name
	end

	f:close()

	return list
end

local function get_versions(fn)
	local f, err = io.open(fn, "r")
	if not f then
		return 0, "develop"
	end
	local v = tonumber(f:read("l"))
	local gv = f:read("l")
	f:close()
	return v, gv
end

_M.version = function()
	local v, gv = get_versions("./iot/version")
	return v, gv
end

_M.skynet_version = function()
	local v, gv = get_versions("./version")
	return v, gv
end

local plat_names = {
	armv5tejl = 'mx0',
	armv7l = 'openwrt',
	x86_64 = 'amd64',
}

_M.skynet_platform = function()
	local uname = _M.uname('-m')
	local plat = plat_names[uname]
	return assert(plat or os.getenv("IOT_PLATFORM"))
end

return _M
