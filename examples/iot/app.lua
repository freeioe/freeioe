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
	return {
		sys = "System Device Statistics",
	}
end

function app:list_props(device)
	return {
		cpuload = "Upload device cpu-load every minutes",
		uptime = "Upload device uptime every minutes",
		startime = "Upload device start-time every minutes",
	}
end

function app:run(tms)
	if not self._start_time then
		self._start_time = self._sys:start_time()
		self._dev:set_prop_value('startime', "current", self._start_time)
	end
	self._dev:set_prop_value('uptime', "current", self._sys:now())
	local loadavg = sysinfo.loadavg()
	self._dev:set_prop_value('cpuload', "current", loadavg.lavg_1)
	return 1000 * 60
end

return app
