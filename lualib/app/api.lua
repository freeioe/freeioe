local skynet = require 'skynet'
local snax = require 'skynet.snax'
local log = require 'utils.log'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'

local api = class("APP_MGR_API")
local dev_api = class("APP_MGR_DEV_API")

function api:initialize(app_name, mgr_snax, cloud_snax)
	self._app_name = app_name
	self._mgr_snax = mgr_snax or snax.uniqueservice('appmgr')
	self._cloud_snax = cloud_snax or snax.uniqueservice('cloud')
end

function api:data_dispatch(channel, source, cmd, app, sn, ...)
	--log.trace('Data Dispatch', channel, source, cmd, app, sn, ...)
	local f = self._handler['on_'..cmd]
	if f then
		return f(app, sn, ...)
	else
		log.trace('No handler for '..cmd)
	end
end

function api:ctrl_dispatch(channel, source, ctrl, app, sn, ...)
	if app == self._app_name then
		return
	end
	--log.trace('Ctrl Dispatch', channel, source, ctrl, app, sn, ...)
	local f = self._handler['on_'..ctrl]
	if f then
		return f(app, sn, ...)
	else
		log.trace('No handler for '..ctrl)
	end
end

function api:comm_dispatch(channel, source, ...)
	--log.trace('Comm Dispatch', channel, source, ...)
	local f = self._handler.on_comm
	if f then
		return f(...)
	else
		log.trace('No handler for on_comm')
	end
end

function api:set_handler(handler, watch_data)
	self._handler = handler
	local mgr = self._mgr_snax

	if handler then
		self._data_chn = mc.new ({
			channel = mgr.req.get_channel('data'),
			dispatch = function(channel, source, ...)
				self.data_dispatch(self, channel, source, ...)
			end
		})
		if watch_data then
			self._data_chn:subscribe()
		end
	else
		if self._data_chn then
			self._data_chn:unsubscribe()
			self._data_chn = nil
		end
	end

	if handler then
		self._ctrl_chn = mc.new ({
			channel = mgr.req.get_channel('ctrl'),
			dispatch = function(channel, source, ...)
				self.ctrl_dispatch(self, channel, source, ...)
			end
		})
		if handler.on_ctrl or handler.on_output or handler.on_command then
			self._ctrl_chn:subscribe()
		end
	else
		if self._ctrl_chn then
			self._ctrl_chn:unsubscribe()
			self._ctrl_chn = nil
		end
	end

	if handler then
		self._comm_chn = mc.new ({
			channel = mgr.req.get_channel('comm'),
			dispatch = function(channel, source, ...)
				self.comm_dispatch(self, channel, source, ...)
			end
		})
		if handler.on_comm then
			self._comm_chn:subscribe()
		end
	else
		if self._comm_chn then
			self._comm_chn:unsubscribe()
			self._comm_chn = nil
		end
	end
end

--[[
-- List devices
--]]
function api:list_devices()
	return dc.get('DEVICES')
end

function api:add_device(sn, inputs, outputs, commands)
	local props = {inputs = inputs, outputs = outputs, commands = commands}
	dc.set('DEVICES', sn, props)
	self._data_chn:publish('add_device', self._app_name, sn, props)
	return dev_api:new(self, sn, props)
end

function api:del_device(dev)
	local sn = dev._sn
	local props = dev._props
	dev:clean_up()
	dc.set('DEVICES', sn, nil)
	self._data_chn:publish('del_device', self._app_name, sn, props)
	return true
end

-- Get readonly device object to access input / fire command / output
function api:get_device(sn)
	local props = dc.get('DEVICES', sn)
	return dev_api:new(self, sn, props, true)
end

-- Applicaiton control
function api:send_ctrl(app, ctrl, params)
	self._ctrl_chn:publish('ctrl', self._app_name, app, cmd, params)
end

function api:_dump_comm(sn, dir, ...)
	assert(sn)
	return self._comm_chn:publish(self._app_name, sn, dir, skynet.time(), ...)
end

--[[
-- Get device configuration string by device serial number(sn)
--]]
function api:get_conf(sn)
	return self._cloud_snax.req.get_device_conf(sn)
end

--[[
-- Set device configuration string
--]]
function api:set_conf(sn, conf)
	return self._cloud_snax.req.set_device_conf(sn)
end


function dev_api:initialize(api, sn, props, readonly)
	self._sn = sn
	self._props = props
	self._app_name = api._app_name
	self._data_chn = api._data_chn
	self._ctrl_chn = api._ctrl_chn
	self._comm_chn = api._comm_chn
	self._readonly = readonly

	self._inputs_map = {}
	for _, t in ipairs(props.inputs) do
		self._inputs_map[t.name] = true
	end
end

function dev_api:clean_up()
	self._app_name = nil
	self._sn = nil
	self._props = nil
	self._inputs_map = nil
	self._data_chn = nil
end

function dev_api:mod(inputs, outputs, commands)
	assert(not self._readonly, "This is not created device")
	self._props = {
		inputs = inputs,
		outputs = outputs,
		commands = commands,
	}

	self._inputs_map = {}
	for _, t in ipairs(inputs) do
		self._inputs_map[t.name] = true
	end
	dc.set('DEVICES', sn, props)

	self._data_chn:publish('mod_device', self._app_name, self._sn, props)
	return true
end

function dev_api:get_input_prop(input, prop)
	return dc.set('INPUT', self._sn, input, prop)
end

function dev_api:set_input_prop(input, prop, value, timestamp, quality)
	assert(not self._readonly, "This is not created device")
	assert(input and prop and value)
	if not self._inputs_map[input] then
		return nil, "Property "..input.." does not exits in device "..self._sn
	end

	dc.set('INPUT', self._sn, input, prop, value)
	self._data_chn:publish('input', self._app_name, self._sn, input, prop, value, timestamp or skynet.time(), quality or 0)
	return true
end

function dev_api:set_output_prop(output, prop, value)
	dc.set('OUTPUT', self._sn, output, prop, value)
	self._ctrl_chn:publish('output', self._app_name, self._sn, input, prop, value, skynet.time())
	return true
end

function dev_api:get_output_prop(output, prop)
	return dc.get('OUTPUT', self._sn, output, prop)
end

function dev_api:send_command(command, param)
	self._ctrl_chn:publish("command", self._app_name, self._sn, command, param)
	return true
end

function dev_api:list_props()
	return self._props
end

function dev_api:dump_comm(dir, ...)
	return self._comm_chn:publish(self._app_name, self._sn, dir, skynet.time(), ...)
end

return api
