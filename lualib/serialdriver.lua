local skynet = require 'skynet'
local rs232 = require 'rs232'
local class = require 'middleclass'

local serial = class("SerialClass")

local function convert_number(val)
	if type(val) == 'number' then
		return tostring(math.floor(val))
	end
	return val
end

function serial:initialize(port, baudrate, data_bits, parity, stop_bits, flowcontrol)
	assert(port, "Port is requried")
	self._port_name = port
	self._opts = {
		baud = '_'..(convert_number(baudrate) or 9600),
		data_bits = '_'..(convert_number(data_bits) or 8),
		parity = string.upper(parity or "NONE"),
		stop_bits = '_'..(convert_number(stop_bits) or 1),
		flow_control = string.upper(flowcontrol or "OFF")
	}
end

function serial:open()
	local port, err = rs232.port(self._port_name, self._opts)
	if not port then
		return nil, err
	end
	local ok, err = port:open()
	if not ok then
		return nil, tostring(err)
	end
	self._port = port

	return port
end

local function bind_func(serial, name)
	serial[name] = function(obj, ...)
		local port = obj._port
		assert(port, "port does not exits")
		return port[name](port, ...)
	end
end

bind_func(serial, "close")
bind_func(serial, "write")
--bind_func(serial, "read")
bind_func(serial, "flush")
bind_func(serial, "in_queue_clear")
bind_func(serial, "in_queue")
bind_func(serial, "device")
--bind_func(serial, "fd")
function serial:fd()
	assert(self._port)
	return self._port._p:fd()
end
bind_func(serial, "set_baud_rate")
bind_func(serial, "baud_rate")
bind_func(serial, "set_data_bits")
bind_func(serial, "data_bits")
bind_func(serial, "set_stop_bits")
bind_func(serial, "stop_bits")
bind_func(serial, "set_parity")
bind_func(serial, "parity")
bind_func(serial, "set_flow_control")
bind_func(serial, "flow_control")
bind_func(serial, "set_dtr")
bind_func(serial, "dtr")
bind_func(serial, "set_rts")
bind_func(serial, "rts")

--- 
-- serial start function
-- @tparam function cb callback function. e.g. function(data, err) end
-- @tparam number timeout serial reading timeout (in ms)
function serial:start(cb, timeout)
	local port = self._port
	local timeout = timeout or 10
	assert(port)
	skynet.fork(function()
		while true do
			if not port._p then
				cb(nil, "Serial port closed!")
				break
			end
			local len, err = port:in_queue()
			if len and len > 0 then
				local data, err = port:read(len, timeout)
				--print("SERIAL:", len, data, err)
				cb(data, err)
				if not data then
					break
				end
			end
			skynet.sleep(1)
		end
	end)
end

return serial
