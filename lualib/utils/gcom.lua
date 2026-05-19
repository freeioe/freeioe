local sysinfo = require 'utils.sysinfo'
local lfs = require 'lfs'

local _M = {}

-- 验证串口设备名称
local function validate_port(port)
	-- 只允许 /dev/ttyXXX 或 /dev/ttyUSBXX 格式
	if not port or type(port) ~= 'string' then
		return nil, "Invalid port type"
	end
	if not string.match(port, '^/dev/tty[%w]+') then
		return nil, "Invalid port format"
	end
	return true
end

-- 验证脚本文件名
local function validate_script(script)
	if not script or type(script) ~= 'string' then
		return nil, "Invalid script type"
	end
	-- 只允许字母数字、下划点、短横线
	if not string.match(script, '^[%w%._-]+$') then
		return nil, "Invalid script name"
	end
	-- 拒绝路径遍历
	if string.match(script, '%.%.') then
		return nil, "Path traversal not allowed"
	end
	return true
end

_M.exec = function(port, script)
	local ok, err = validate_port(port)
	if not ok then return nil, err end
	local ok, err = validate_script(script)
	if not ok then return nil, err end
	return sysinfo.exec('gcom -d '..port..' -s '..script)
end

_M.get_boardname = function()
	if _M._board_name then
		return _M._board_name
	end
	local f, err = io.open('/tmp/sysinfo/board_name', 'r')
	if f then
		local s = f:read("l")
		f:close()
		if s then
			if string.match(s, 'Q2040') then
				_M._board_name = 'Q204'
			elseif string.match(s, 'tgw303x') then
				_M._board_name = 'Q102'
			elseif string.match(s, 'F202') then
				_M._board_name = 'F208'
			end
		end
	end
	return _M._board_name or 'Unknown'
end

_M.detect_device = function()
	if _M._dev_tty then
		return _M._dev_tty
	end

	local bname = _M.get_boardname()
	if bname == 'Q204' or bname == 'F208' then
		_M._dev_tty = '/dev/ttyUSB2'
	end
	if bname == 'Q102' then
		local mode = lfs.attributes('/dev/ttyUSB3', 'mode')
		if mode then
			_M._dev_tty = '/dev/ttyUSB3'
		end
		return _M._dev_tty or '/dev/ttymxc3'
	end

	return _M._dev_tty or '/dev/tty0'
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
	-- 生成安全的临时文件名，包含随机数防止竞态条件
	local random_suffix = string.format("%04x", math.random(0, 65535))
	local path = '/tmp/__gcom_'..script..'_'..random_suffix
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
	if not port then
		return nil, err
	end

	-- 验证脚本名称
	local ok, err = validate_script(script)
	if not ok then
		return nil, err
	end

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
