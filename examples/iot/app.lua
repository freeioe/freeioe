local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local datacenter = require 'skynet.datacenter'

local app = class("IOT_SYS_APP_CLASS")
app.API_VER = 1

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()
end

function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			print('on_output', app, sn, output, prop, value)
			return true, "done"
		end,
		on_command = function(app, sn, command, param)
			print('on_command', app, sn, command, param)
			return true, "eee"
		end,
		on_ctrl = function(app, command, param, ...)
			print('on_ctrl', app, command, param, ...)
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
		{
			name = "platform",
			desc = "Skynet Platform type",
			vt = "string",
		},
		{
			name = "data_upload",
			desc = "Upload data to cloud",
			vt = "int",
		},
		{
			name = "stat_upload",
			desc = "Upload statictis data to cloud",
			vt = "int",
		},
		{
			name = "comm_upload",
			desc = "Upload communication data to cloud",
			vt = "int",
		},
		{
			name = "log_upload",
			desc = "Upload logs to cloud",
			vt = "int",
		},
		{
			name = "enable_beta",
			desc = "Device using beta enable flag",
			vt = "int",
		}
	}
	local meta = self._api:default_meta()
	meta.name = "Bamboo IOT"
	meta.description = "Bamboo IOT Device"
	meta.series = "Q102" -- TODO:
	self._dev = self._api:add_device(sys_id, meta, inputs)

	return true
end

function app:close(reason)
	--print(self._name, reason)
	if self._cancel_uptime_timer then
		self._cancel_uptime_timer()
		self._cancel_uptime_timer = nil
	end
end

function app:run(tms)
	if not self._start_time then
		self._start_time = self._sys:start_time()
		local v, gv = sysinfo.version()
		self._log:notice("System Version:", v, gv)
		local sv, sgv = sysinfo.skynet_version()
		self._log:notice("Skynet Platform Version:", sv, sgv)
		local plat = sysinfo.platform() or "unknown"

		self._dev:set_input_prop('starttime', "value", self._start_time)
		self._dev:set_input_prop('version', "value", v)
		self._dev:set_input_prop('version', "git_version", gv)
		self._dev:set_input_prop('skynet_version', "value", sv)
		self._dev:set_input_prop('skynet_version', "git_version", sgv)
		self._dev:set_input_prop('platform', "value", plat)

		local calc_uptime = nil
		calc_uptime = function()
			self._dev:set_input_prop('uptime', "value", self._sys:now())
			self._cancel_uptime_timer = self._sys:cancelable_timeout(1000 * 60, calc_uptime)
		end
		calc_uptime()

		--[[
		self._sys:timeout(100, function()
			self._log:debug("Fire event")
			local data = {
				['type'] = "EEE",
				info = "System Started!"
			}
			local level = 0
			self._dev:fire_event(level, data, self._sys:time())
		end)
		]]--
	end

	local loadavg = sysinfo.loadavg()
	self._dev:set_input_prop('cpuload', "value", tonumber(loadavg.lavg_15))
	
	-- cloud flags
	--
	local enable_data_upload = datacenter.get("CLOUD", "DATA_UPLOAD")
	local enable_stat_upload = datacenter.get("CLOUD", "STAT_UPLOAD")
	local enable_comm_upload = datacenter.get("CLOUD", "COMM_UPLOAD")
	local enable_log_upload = datacenter.get("CLOUD", "LOG_UPLOAD")
	local enable_beta = datacenter.get('CLOUD', 'USING_BETA')

	self._dev:set_input_prop('data_upload', 'value', enable_data_upload and 1 or 0)
	self._dev:set_input_prop('stat_upload', 'value', enable_stat_upload  and 1 or 0)
	self._dev:set_input_prop('comm_upload', 'value', enable_comm_upload or 0)
	self._dev:set_input_prop('log_upload', 'value', enable_log_upload or 0)
	self._dev:set_input_prop('enable_beta', 'value', enable_beta and 1 or 0)

	if math.abs(os.time() - self._sys:time()) > 2 then
		self._log:error("Time diff found, system will be rebooted in five seconds. ", os.time(), self._sys:time())
		local level = 0
		local data = {
			['type'] = "EEE",
			info = "Time diff found!"
		}
		self._dev:fire_event(level, data)
		self._sys:timeout(500, function()
			self._sys:abort()
		end)
	else
		--print(os.time() - self._sys:time())
	end

	return 1000 * 5
end

return app
