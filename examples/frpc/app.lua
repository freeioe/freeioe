local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local pm = require 'process_monitor'
local inifile = require 'inifile'
local cjson = require 'cjson'

local app = class("FREEIOE_APP_FRP_CLASS")
app.API_VER = 1

local function get_default_conf(sys, conf)
	local ini_conf = {}
	local id = sys:id()

	ini_conf.common = {
		server_addr = conf.server_addr or 'frp.symgrid.com',
		server_port = conf.server_port or '5443',
		token = conf.token or 'IOT1@SYMGRID.COM',
		protocol = conf.protocol or 'kcp',
		log_file = '/tmp/ioe_frpc_'..sys._app_name..'.log',
		log_level = 'info',
		log_max_days = 1,
		login_fail_exit = false,
	}

	if conf.enable_web then
		ini_conf[id..'__web'] = {
			['type'] = 'http',
			local_port = 8808,
			subdomain = string.lower(id),
			use_encryption = true,
			use_compression = true,
		}
	end
	if conf.enable_debug then
		ini_conf[id..'__debug'] = {
			['type'] = 'tcp',
			sk = string.lower(id),
			local_ip = '127.0.0.1',
			local_port = 7000,
			use_encryption = true,
			use_compression = true,
		}
	end

	for k,v in pairs(conf.visitors or {}) do
		if v.use_encryption == nil then
			v.use_encryption = true
		end
		if v.use_compression == nil then
			v.use_compression = true
		end
		ini_conf[id..'_'..k] = v
	end

	local visitors = {}
	for k,v in pairs(ini_conf) do
		if k ~= 'common' then
			visitors[#visitors + 1] = k
		end
	end

	return ini_conf, visitors
end


function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()
	self._ini_file = sys:app_dir()..".frpc.ini"

	local conf, visitors = get_default_conf(sys, self._conf)
	inifile.save(self._ini_file, conf)
	self._visitors = cjson.encode(visitors)

	local frpc_bin = sys:app_dir().."/bin/frpc"
	self._pm = pm:new(self._name, frpc_bin, {'-c', self._ini_file})
end

function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			self._log:trace('on_output', app, sn, output, prop, value)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			if output == 'config' then
				self._log:notice('Try to change FRPC configuration, value:', value)
				if type(value) ~= 'table' then
					local conf, err = cjson.decode(value)
					if not conf then
						self._log:error('Incorrect configuration value found, value:', value)
						return false, "Incorrect configuration value found"
					end
					value = conf
				end
				self._conf = value

				local conf, visitors = get_default_conf(self._sys, self._conf)
				inifile.save(self._ini_file, conf)
				self._visitors = cjson.encode(visitors)

				if conf.auto_start then
					self._sys:post('pm_ctrl', 'restart')
				else
					self._sys:post('pm_ctrl', 'stop')
				end
				return true
			end
			if output == 'enable_heartbeat' then
				self._log:notice('Enable hearbeat for keeping FRPC running, value:', value)
				self._conf.enable_heartbeat = value
				self._heartbeat_timeout = self._sys:time() + 60
				return true
			end
			if output == 'heartbeat' then
				self._log:trace('Hearbeat for keeping FRPC running, value:', value)
				local timeout = tonumber(value) or 60
				self._heartbeat_timeout = self._sys:time() + timeout
				return true
			end
			return true, "done"
		end,
		on_command = function(app, sn, command, param)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			-- command: start, stop, restart
			local f = self._pm[command]
			if f then
				local r, err = f(self._pm)
				if not r then
					self._log:error(err)
				end
				if command == 'start' or command == 'restart' then
					self:on_frpc_start()
				end
				return r, err
			else
				self._log:error('device command not exists!', command)
				return false, 'device command not exists!'
			end
		end,
		on_ctrl = function(app, command, param, ...)
			self._log:trace('on_ctrl', app, command, param, ...)
		end,
	})

	local dev_sn = self._sys:id()..'.'..self._name
	local inputs = {
		{
			name = "starttime",
			desc = "frpc start time in UTC",
			vt = "int",
		},
		{
			name = "uptime",
			desc = "frpc process uptime",
			vt = "int",
		},
		{
			name = "frpc_run",
			desc = "frpc process running status",
			vt = "int",
		},
		{
			name = "frpc_visitors",
			desc = "current enabled frpc visitors",
			vt = "string"
		},
		{
			name = "enable_heartbeat",
			desc = "frpc process keep running with heartbeat",
			vt = "int",
		},
		{
			name = "heartbeat_timeout",
			desc = "Running heartbeat timeout",
		},
		{
			name = "config",
			desc = "frpc configuration (json)",
			vt = "string",
		},
	}
	local outputs = {
		{
			name = "config",
			desc = "frpc configuration (json)",
			vt = "string",
		},
		{
			name = "enable_heartbeat",
			desc = "Change frpc process keep running with heartbeat",
			vt = "int",
		},
		{
			name = "heartbeat",
			desc = "Heartbeat output",
		},
	}
	local cmds = {
		{
			name = "start",
			desc = "start frpc process",
		},
		{
			name = "stop",
			desc = "stop frpc process",
		},
		{
			name = "restart",
			desc = "restart frpc process",
		},
	}

	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "FRPC Client"
	meta.description = "FRPC Client Running Status"
	meta.series = "X"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)

	return true
end

function app:close(reason)
	self._pm:stop()
	--print(self._name, reason)
	self:on_frpc_stop()
end

function app:on_frpc_start()
	if self._start_time then
		self:on_frpc_stop()
	end

	self._start_time = self._sys:time()
	self._uptime_start = self._sys:now()
	self._dev:set_input_prop('starttime', 'value', self._start_time)
	self._dev:set_input_prop('config', 'value', cjson.encode(self._conf))

	self._dev:set_input_prop('enable_heartbeat', 'value', self._conf.enable_heartbeat and 1 or 0)
	self._dev:set_input_prop('heartbeat_timeout', 'value', self._heartbeat_timeout or 0)

	self._dev:set_input_prop('frpc_visitors', 'value', self._visitors)

	local calc_uptime = nil
	calc_uptime = function()
		self._dev:set_input_prop('uptime', 'value', self._sys:now() - self._uptime_start)
		self._cancel_uptime_timer = self._sys:cancelable_timeout(1000 * 60, calc_uptime)
		if self._conf.enable_heartbeat then
			if self._sys:time() > (self._heartbeat_timeout + 10) then
				self._log:warning('Frpc running heartbeat rearched, close frpc')
				self._sys:post('pm_ctrl', 'stop')
			end
		end
	end
	calc_uptime()
end

function app:on_frpc_stop()
	if self._cancel_uptime_timer then
		self._cancel_uptime_timer()
		self._cancel_uptime_timer = nil
		self._start_time = nil
		self._uptime_start = nil
	end
	self._pm:cleanup()
end

function app:run(tms)
	if not self._first_start then
		self._pm:stop()
		self._pm:cleanup()
		--self._sys:sleep(500)

		if self._conf.auto_start then
			self._pm:start()
			self:on_frpc_start()
		end
		self._first_start = true
	end

	local status = self._pm:status()
	self._dev:set_input_prop('frpc_run', 'value', status and 1 or 0)

	-- for heartbeat stuff
	self._dev:set_input_prop('enable_heartbeat', 'value', self._conf.enable_heartbeat and 1 or 0)
	self._dev:set_input_prop('heartbeat_timeout', 'value', self._heartbeat_timeout or 0)

	return 1000 * 5
end

function app:on_post_pm_ctrl(action)
	if action == 'restart' then
		self._log:debug("Restart frpc(process-monitor)")
		local r, err = self._pm:restart()
		if r then
			self:on_frpc_start()
		--[[
			self._sys:set_conf(self._conf)
		]]--
		end
	end
	if action == 'stop' then
		self._log:debug("Stop frpc(process-monitor)")
		self._pm:stop()
		self:on_frpc_stop()
	end
end
return app
