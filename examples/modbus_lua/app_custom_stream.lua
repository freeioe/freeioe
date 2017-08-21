local class = require 'middleclass'
local socket = require 'skynet.socket'
local modbus = require 'modbus.init'

local app = class("XXXX_App")

function app:initialize(name, conf, sys)
	self._name = name
	self._conf = conf
	self._sys = sys
	self._api = sys:data_api()
	self._log = sys:logger()
	self._log:debug(name.." Application initlized")
end

function app:start()
	local stream = socket.open("127.0.0.1", 1502)
	self._stream = stream
	self._client1 = modbus.client({
		send = function(msg)
			self._dev1:dump_comm('OUT', msg)
			socket.write(stream, msg)
		end,
		read = function(check, timeout)
			timeout = os.time() + timeout
			local buf = ""
			local pdu = nil
			local need_len = 5
			while os.time() < timeout do
				local str, err = socket.read(stream, need_len)
				if not str then
					return nil, err
				end
				self._dev1:dump_comm('IN', str)
				buf = buf..str
				pdu, buf, need_len = check(buf)
				if pdu then
					return pdu
				end
			end
			return nil, "timeout"
		end,
	}, modbus.apdu_tcp, 1)

	self._api:set_handler({
		on_ctrl = function(...)
			print(...)
		end,
	})
	local args = {}
	for i = 1, 10 do
		args[#args + 1] = { 
			name='tag'..i,
			desc='tag'..i..' description',
		}
	end
	self._dev1 = self._api:add_device("xxxx", args)
	--self._api:del_device("xxxx")

	return true
end

function app:close(reason)
	print(self._name, reason)
end

function decode_registers(raw, count)
	local d = modbus.decode
	local len = d.uint8(raw, 2)
	assert(len >= count * 2)
	local regs = {}
	for i = 0, count - 1 do
		regs[#regs + 1] = d.uint16(raw, i * 2 + 3)
	end
	return regs
end

function app:run(tms)
	local client = self._client1
	if not client then
		return
	end

	local base_address = 0x00
	local req = {
		func = 0x03,
		addr = base_address,
		len = 10,
	}
	local raw, err = client:request(req, 1000)
	if not raw then 
		self._log:error("read failed: " .. err) 
		return
	end
	local regs = decode_registers(raw, 10)

	for r,v in ipairs(regs) do
		self._dev1:set_input_prop('tag'..r, "value", math.tointeger(v))
	end

	return tms
end

return app
