local lfs = require 'lfs'
local skynet = require 'skynet'

local ioe_path = '/usr/ioe/freeioe'

local file_removed = {
	'lualib/app/port.lua',
	'lualib/app/port_helper.lua',
	'lualib/app/serial.lua',
	'lualib/app/socket.lua',
}

local function upgrade_fix()
	for _, fn in ipairs(file_removed) do
		if lfs.attributes('mode', ioe_path..'/'..fn) == 'file' then
			skynet.error('Remove file:', fn)
			os.execute('rm -f '..ioe_path..'/'..fn)
		end
	end
end


return upgrade_fix
