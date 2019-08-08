local skynet = require 'skynet'
local lfs = require 'lfs'
local sysinfo = require 'utils.sysinfo'
local gpio_test = require 'hwtest.gpio'

local exec = sysinfo.exec

local list_modem = function(eth_name, usb_id)
	local str = exec('lsusb')
	if not str then
		return nil, err
	end

	if not str:find(usb_id) then
		return nil, "Not found USB"
	end

	local str = exec('ifconfig '..eth_name)
	return str:find('HWaddr')
end

return function(eth_name, usb_id)
	local eth_name = eth_name or 'eth1'
	local usb_id = usb_id or '0b95:772b'

	local check_present = function()
		for i = 1, 3 do
			local r, err = list_modem(eth_name, usb_id)
			if r then
				return true
			end
			skynet.sleep(100)
		end
		return false, "USB not found"
	end
	local check_not_present = function()
		for i = 1, 3 do
			local r, err = list_modem(eth_name, usb_id)
			if not r then
				return true
			end
			skynet.sleep(100)
		end
		return false, "USB existing!!!"
	end

	return gpio_test(eth_name..'_reset', true, check_not_present, check_present)
end
