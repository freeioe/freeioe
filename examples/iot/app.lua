local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'

local app = class("IOT_SYS_APP_CLASS")

function app:initialize(name, conf, sys)
	self._name = name
	self._conf = conf
	self._sys = sys
	self._api = self._sys:data_api()
	self._log = sys:logger()
end

function app:start()
	self._api:set_handler({
		on_output = function(...)
			print('on_output', ...)
		end,
		on_command = function(...)
			print('on_command', ...)
		end,
		on_ctrl = function(...)
			print('on_ctrl', ...)
		end,
	})

	local sys_id = self._sys:id()
	local inputs = {
		{
			name = 'cpuload',
			desc = 'System CPU Load'
		},
		{
			name = "uptime",
			desc = "System uptime",
			vt = "int",
		},
		{
			name = "starttime",
			desc = "System start time in UTC",
			vt = "int",
		},
		{
			name = "version",
			desc = "System Version",
			vt = "int",
		},
		{
			name = "skynet_version",
			desc = "Skynet Platform Version",
			vt = "int",
		},
	}
	self._dev = self._api:add_device(sys_id, inputs)

	return true
end

function app:close(reason)
	--print(self._name, reason)
	if self._cancel_uptime_timer then
		self._cancel_uptime_timer()
		self._cancel_uptime_timer = nil
	end
end

local function get_versions(fn)
	local f, err = io.open(fn, "r")
	if not f then
		return 0, "develop"
	end
	local v = tonumber(f:read("l"))
	local gv = f:read("l")
	f:close()
	return v, gv
end

function app:run(tms)
	if not self._start_time then
		self._start_time = self._sys:start_time()
		local v, gv = get_versions("./iot/version")
		self._log:notice("System Version:", v, gv)
		local sv, sgv = get_versions("./version")
		self._log:notice("Skynet Platform Version:", sv, sgv)

		self._dev:set_input_prop('starttime', "value", self._start_time)
		self._dev:set_input_prop('version', "value", v)
		self._dev:set_input_prop('version', "git_version", gv)
		self._dev:set_input_prop('skynet_version', "value", sv)
		self._dev:set_input_prop('skynet_version', "git_version", sgv)

		local calc_uptime = nil
		calc_uptime = function()
			self._dev:set_input_prop('uptime', "value", self._sys:now())
			self._cancel_uptime_timer = self._sys:cancelable_timeout(1000 * 60, calc_uptime)
		end
		calc_uptime()
	end

	local loadavg = sysinfo.loadavg()
	self._dev:set_input_prop('cpuload', "value", tonumber(loadavg.lavg_15))
	return 1000 * 5
end

return app
