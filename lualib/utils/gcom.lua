local sysinfo = require 'utils.sysinfo'
local lfs = require 'lfs'

local _M = {}

_M.exec = function(port, script)
	return sysinfo.exec('gcom -d '..port..' -s '..script)
end

_M.detect_device = function()
	local mode = lfs.attributes('/dev/ttyUSB3', 'mode')
	if mode then
		return '/dev/ttyUSB3'
	end
	return '/dev/ttymxc3'
end

_M.gen_gcom_script = function(at_cmd)
	local script = [[opengt
 set com 115200n81
 set comecho off
 set senddelay 0.02
 waitquiet 0.2 0.2
 flash 0.1

:start
 send "AT+%s^m"
 get 1 "" $s
 print $s

:continue
 exit 0
 ]]
	return string.format(script, at_cmd)
end

_M.create_gcom_script = function(script, at_cmd)
	local path = '/tmp/__gcom_'..script
	local f, err = io.open(path, 'w+')
	if not f then
		return nil, err
	end
	f:write(_M.gen_gcom_script(at_cmd))
	f:close()
	return path
end

_M.auto_port_exec = function(script, at_cmd)
	local port, err = _M.detect_device()
	local script_path = '/etc/gcom/'..script
	if 'file' ~= lfs.attributes(script_path, 'mode') then
		script_path, err = _M.create_gcom_script(script, at_cmd)
		if not script_path then
			return nil, err
		end
	end
	return _M.exec(port, script_path)
end

--- CCID sim card id
_M.get_ccid = function()
	local s, err = _M.auto_port_exec('getccid.gcom', 'CCID')
	if not s then
		return nil, err
	end

	local ccid = string.match(s, '+CCID:%s-(%w+)')
	if not ccid then
		return nil, s
	end
	return ccid	
end

--- CSQ -- signal strength
_M.get_csq = function(script_dir)
	local s, err = _M.auto_port_exec('getstrength.gcom', 'CSQ')
	if not s then
		return nil, err
	end

	local val = string.match(s, '+CSQ:%s-(%d+)')
	if not val then
		return nil, s
	end
	return tonumber(val)
end

--- CPSI -- work mode
_M.get_cpsi = function(script_dir)
	local s, err = _M.auto_port_exec('getCPSI.gcom', 'CPSI?')
	if not s then
		return nil, err
	end

	local patt = '%g'
	if _VERSION == 'Lua 5.1' then
		patt = '[^%s]'
	end

	local val = string.match(s, '+CPSI:%s-('..patt..'+)')
	if not val then
		return nil, s
	end
	return val	
end

return _M
