local class = require 'middleclass'
local skynet = require 'skynet'
local mc = require 'skynet.multicast'

local usb = class('IOE.UEVENT.USB')

function usb:initialize(dev_name, callback)
	self._dev_name = dev_name
	self._callback = callback
	local chn = skynet.call(".uevent", "lua", "channel")
	self._chn = mc.new ({
		channel = chn, 
		dispatch = function(channel, source, ...)
			self:on_uevent(channel, source, ...)
		end
	})
	self._chn:subscribe()
end

function usb:on_uevent(channel, source, msg)
	if msg.SUBSYSTEM ~= 'usb' then
		return
	end
	if msg.DEVTYPE ~= 'usb_device' then
		return
	end

	print(msg.ACTION, msg.DEVNAME)
	if msg.DEVNAME == self._dev_name then
		self._callback(msg.ACTION, msg)
	end
end

function usb:close()
	self._chn:unsubscribe()
	self._chn = nil
end

return usb
