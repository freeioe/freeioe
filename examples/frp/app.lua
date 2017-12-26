local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local pm = require 'process_monitor'
local inifile = require 'inifile'

local app = class("IOT_APP_FRP_CLASS")
app.API_VER = 1

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()

	local ini_conf = {
		common = {
			server_addr = 'm2mio.com',
			server_port = '5443',
			privilege_token = 'BWYJVj2HYhVtdGZL',
		}
	}
	ini_conf[sys:id()..'_web'] = {
		['type'] = 'http',
		local_port = 8808,
		custom_domains = 'symgrid.com',
		subdomain = sys:id(),
	}
	local ini_file = sys:app_dir().."frpc.ini"
	inifile.save(ini_file, ini_conf)

	--local frp_bin = sys:app_dir().."arm/frpc"
	local frp_bin = sys:app_dir().."amd64/frpc"
	self._pm = pm:new(self._name, frp_bin, {'-c', ini_file})
end

function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			print('on_output', app, sn, output, prop, value)
			return true, "done"
		end,
		on_command = function(app, sn, command, param)
			if sn ~= self._sys:id()..'.frp' then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			local f = self._pm[command]
			if f then
				local r, err = f(self._pm)
				if not r then
					self._log:error(err)
				end
				return r, err
			else
				self._log:error('device command not exists!', command)
				return false, 'device command not exists!'
			end
		end,
		on_ctrl = function(app, command, param, ...)
			print('on_ctrl', app, command, param, ...)
		end,
	})

	local sys_id = self._sys:id()..'.'..self._name
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
			name = "frp_run",
			desc = "frp process running status",
			vt = "int",
		},
		{
			name = "frp_config",
			desc = "frp configuration",
			vt = "string",
		},
	}
	local outputs = {
		{
			name = "frp_config",
			desc = "frp configuration",
			vt = "string",
		},
	}
	local cmds = {
		{
			name = "start",
		},
		{
			name = "stop",
		},
	}

	self._dev = self._api:add_device(sys_id, inputs, outputs, cmds)

	--self._pm:start()

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
		self._dev:set_input_prop('starttime', "value", self._start_time)

		local calc_uptime = nil
		calc_uptime = function()
			self._dev:set_input_prop('uptime', "value", self._sys:now())
			self._cancel_uptime_timer = self._sys:cancelable_timeout(1000 * 60, calc_uptime)
		end
		calc_uptime()
	end

	local loadavg = sysinfo.loadavg()
	self._dev:set_input_prop('cpuload', "value", tonumber(loadavg.lavg_15))

	local status = self._pm:status()
	self._dev:set_input_prop('frp_run', "value", status and 1 or 0)
	return 1000 * 5
end

return app
