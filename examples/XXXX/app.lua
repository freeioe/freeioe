local class = require 'middleclass'
local serial = require 'serialdriver'

local app = class("XXXX_App")

function app:initialize(name, conf, sys)
	self._name = name
	self._conf = conf
	self._sys = sys
	self._api = self._sys:data_api()
	sys:log("debug", "XXXX Application initlized")
	print("folder", sys:app_dir())
	--[[
	print(sys:write_json("xx.json", conf))
	print(sys:read_json("xx.json"))
	]]--

	--local modbus = require(name..".modbus")
end

function app:start()
	self._sys:fork(function()
		self._sys:log('debug', 'testing sys:fork')
		self._sys:sleep(1000)
		self._sys:log('debug', 'testing sys:fork end')
	end)

	self._api:set_handler({
		on_input = function(...)
			print(...)
		end,
		on_output = function(...)
			print(...)
		end,
		on_ctrl = function(...)
			print(...)
		end,
	})

	local sn = '666'--self._api:gen_sn()
	self._dev1 = self._api:add_device(sn, {{name="tag1", desc="tag1 desc"}})

	--[[
	local port = serial:new("/tmp/ttyS10", 9600, 8, "NONE", 1, "OFF")
	local r, err = port:open()
	if not r then
		self._sys:log("error", "Failed open port, error: "..err)
		return nil, err
	end
	port:start(function(data, err)
		print(data, err)
	end)
	self._port = port
	]]--
	return true
end

function app:close(reason)
	--[[
	self._port:close()
	self._port = nil
	]]--
	print(self._name, reason)
end

function app:list_devices()
	return {
		{
			name = '666',
			desc = "Description A Device",
		}
	}
end

function app:list_props(device)
	return {
		inputs = {
			{
				name="tag1",
				desc = "Property A Description",
				-- vt = "int",
			}
		}
	}
end

function app:run(tms)
	--[[
	if self._port then
		self._port:write("BBBB")
	end
	]]--
	--self._dev1:set_input_prop('tag1', "value", self._sys:now())
	self._dev1:set_input_prop('tag1', "value", math.random())
	self._sys:dump_comm(nil, "IN", "XXXXXXXXXXXX")
end

return app
