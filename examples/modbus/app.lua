local class = require 'middleclass'
local modbus = require 'libmodbus'

local app = class("XXXX_App")

function app:initialize(name, conf, sys)
	self._name = name
	self._conf = conf
	self._sys = sys
	self._api = sys:data_api()
	sys:log("debug", name.." Application initlized")
end

function app:start()
	--local dev = modbus.new_tcp_pi("127.0.0.1", 1502)
	local dev = modbus.new_rtu("/tmp/ttyS10", 115200, "none", 8, 1)
	dev:set_debug()
	dev:connect()
	self._dev = dev

	self._api:add_device("xxxx", {name="ddddd"})
	return true
end

function app:close(reason)
	print(self._name, reason)
end

function app:list_devices()
	return {
		dev_a = {
			name = "Device A",
			desc = "Description A Device",
		}
	}
end

function app:list_props(device)
	return {
		prop_a = {
			name = "Property A",
			desc = "Property A Description",
		}
	}
end

function app:run(tms)
	self._sys:sleep(tms)
	local dev = self._dev
	if not dev then
		return
	end

	dev:set_slave(1)
	local base_address = 0x00
	local sec, usec = dev:get_byte_timeout()
	print(sec * 1000 + usec / 1000)
	local sec, usec = dev:get_response_timeout()
	print(sec * 1000 + usec / 1000)
	local regs, err = dev:read_registers(base_address, 10)
	if not regs then 
		error("read failed: " .. err) 
	end

	for r,v in ipairs(regs) do
		print(string.format("register (offset %d) %d: %d (%#x): %#x (%d)",
		r, r, r + base_address - 1, r + base_address -1, v, v))
	end

end

return app
