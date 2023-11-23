local class = require 'middleclass'
local skynet = require 'skynet'
local mc = require 'skynet.multicast'

local serial = class('IOE.UEVENT.SERIAL')

function serial:initialize(port, callback)
	self._port = port
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

function serial:on_uevent(channel, source, msg)
	if msg.SUBSYSTEM ~= 'tty' then
		return
	end
	print(msg.ACTION, msg.DEVNAME)
	if msg.DEVNAME == self._port or '/dev/'..msg.DEVNAME == self._port then
		self._callback(msg.ACTION, msg)
	end
end

function serial:close()
	self._chn:unsubscribe()
	self._chn = nil
end

return serial
