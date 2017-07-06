local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'

local app = class("IOT_SYS_APP_CLASS")

function app:initialize(name, conf, sys)
	self._name = name
	self._conf = conf
	self._sys = sys
	self._api = self._sys:data_api()
end

function app:start()
	self._api:set_handler({
		on_output = function(...)
			print(...)
		end,
		on_ctrl = function(...)
			print(...)
		end,
	})

	local sys_id = self._sys:id()
	self._dev = self._api:add_device(sys_id, {"cpuload", "uptime", "starttime"})

	return true
end

function app:close(reason)
	--print(self._name, reason)
end

function app:list_devices()
	local props = self._dev:list_props()
	return {
		sys = "System Device Statistics",
	}
end

function app:list_tpl()
	return {
		{
			name = "System Information Statistics",
			input = {
				cpuload = "Upload device cpu-load every minutes",
				uptime = "Upload device uptime every minutes",
				startime = "Upload device start-time every minutes",
			},
			output = {
			},
			command = {
			}
		},
	}
end

function app:run(tms)
	if not self._start_time then
		self._start_time = self._sys:start_time()
		self._dev:set_input_prop('startime', "value", self._start_time)
	end
	self._dev:set_input_prop('uptime', "value", self._sys:now())
	local loadavg = sysinfo.loadavg()
	self._dev:set_input_prop('cpuload', "value", loadavg.lavg_15)
	return 1000 * 60
end

return app
