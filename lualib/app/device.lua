local skynet = require 'skynet'
local log = require 'utils.log'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'

local device = class("APP_MGR_DEV_API")

function device:initialize(api, sn, props, readonly)
	self._api = api
	self._sn = sn
	self._props = props
	if readonly then
		self._app_name = dc.get('DEV_IN_APP', sn) or api._app_name
	else
		self._app_name = api._app_name
	end
	self._data_chn = api._data_chn
	self._ctrl_chn = api._ctrl_chn
	self._comm_chn = api._comm_chn
	self._readonly = readonly

	self._inputs_map = {}
	for _, t in ipairs(props.inputs) do
		self._inputs_map[t.name] = true
	end

	if not readonly then
		dc.set('DEVICES', sn, props)
		dc.set('DEV_IN_APP', sn, self._app_name)
	end
end

function device:_cleanup()
	self._readonly = true
	self._app_name = nil
	self._sn = nil
	self._props = nil
	self._inputs_map = nil
	self._data_chn = nil
	self._ctrl_chn = nil
	self._comm_chn = nil
	self._api = nil
end

function device:cleanup()
	if self._readonly then
		return
	end

	local sn = self._sn
	local props = self._props

	self._api._devices[sn] = nil

	dc.set('DEVICES', sn, nil)
	dc.set('DEV_IN_APP', sn, nil)

	log.trace("DELETE DEVICE", self._app_name, sn, props)
	self._data_chn:publish('del_device', self._app_name, sn, props)

	self:_cleanup()
end

function device:mod(inputs, outputs, commands)
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

function device:get_input_prop(input, prop)
	return dc.get('INPUT', self._sn, input, prop)
end

function device:set_input_prop(input, prop, value, timestamp, quality)
	assert(not self._readonly, "This is not created device")
	assert(input and prop and value)
	if not self._inputs_map[input] then
		return nil, "Property "..input.." does not exits in device "..self._sn
	end

	dc.set('INPUT', self._sn, input, prop, value)
	self._data_chn:publish('input', self._app_name, self._sn, input, prop, value, timestamp or skynet.time(), quality or 0)
	return true
end

function device:get_output_prop(output, prop)
	return dc.get('OUTPUT', self._sn, output, prop)
end

function device:set_output_prop(output, prop, value)
	dc.set('OUTPUT', self._sn, output, prop, value)
	self._ctrl_chn:publish('output', self._app_name, self._sn, output, prop, value, skynet.time())
	return true
end

function device:send_command(command, param)
	self._ctrl_chn:publish("command", self._app_name, self._sn, command, param)
	return true
end

function device:list_props()
	return self._props
end

function device:dump_comm(dir, ...)
	return self._comm_chn:publish(self._app_name, self._sn, dir, skynet.time(), ...)
end

function device:stat()
	return stat_api:new(self._api, self._sn, self._readonly)
end

return device
