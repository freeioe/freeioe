local skynet = require 'skynet'
local lfs = require 'lfs'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'
local gpio_test = require 'hwtest.gpio'

local exec = sysinfo.exec

local list_modem = function(usb_id)
	local str, err = exec('lsusb')
	if not str then
		return nil, err
	end
	if not str:find(usb_id) then
		return nil, "Not found USB"
	end

	return lfs.attributes('/dev/cdc-wdm0', 'mode') ~= nil
end

return function(gpio_name, usb_id)
	local gpio_name = gpio_name or 'pcie'
	local usb_id = usb_id or '2c7c:0125'

	local check_present = function()
		for i = 1, 30 do
			local r, err = list_modem(usb_id)
			if r then
				log.debug("check_present", "OK!!!")
				return true
			end
			skynet.sleep(100)
		end
		log.debug("check_present", "Not found USB")
		return false, "USB not found"
	end
	local check_not_present = function()
		for i = 1, 30 do
			local r, err = list_modem(usb_id)
			if not r then
				log.debug("check_not_present", "OK!!!")
				return true
			end
			skynet.sleep(100)
		end
		log.debug("check_not_present", "USB existing!!!")
		return false, "USB existing!!!"
	end

	return gpio_test(gpio_name..'_power', false, check_present, check_not_present)
		and gpio_test(gpio_name..'_reset', true, check_not_present, check_present)
end
