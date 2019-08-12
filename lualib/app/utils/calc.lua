local class = require 'middleclass'
local ioe = require 'ioe'
local cov = require 'cov'

local calc = class("APP_UTILS_CALC")

function calc:initialize(sys, api, logger)
	self._sys = sys
	self._api = api
	self._log = logger
	self._triggers = {} --- all triggers key by trigger name
	self._watch_map = {}  -- key is: sn/input/prop
	self._cycle_triggers = {} -- key by trigger name
	self._cov = nil
end

---
-- name: Trigger name(unique)
-- inputs: input array. e.g { {sn='xxxx', input='xxxx', prop='value', default=0} }
-- trigger_cb: your trigger callback function
-- cycle_time: if you want to cycle calling your callback during a time. integer in seconds
function calc:add(name, inputs, trigger_cb, cycle_time)
	assert(self._triggers[name] == nil, "Trigger "..name.." already exits!")
	local cycle_time = math.tointeger(cycle_time)

	local trigger = {
		name = name,
		inputs = inputs,
		callback = trigger_cb
	}

	for _, v in ipairs(inputs) do
		assert(v.sn and v.input and v.prop)
		self:_add_watch(trigger, v)
	end

	self._triggers[name] = trigger

	self:_complete_trigger(trigger)
	
	if cycle_time then
		trigger.cycle =  {
			next_time = (ioe.time() // 1) + cycle_time,
			cycle_time = cycle_time,
		}
		self._cycle_triggers[name] = trigger
	end

	return function()
		local trigger = self._triggers[name]
		if not trigger then
			return nil, "Trigger removed"
		end
		return self:_complete_trigger(trigger)
	end
end

function calc:remove(name)
	self._triggers[name] = nil
	-- TODO: cleanup watch_map and _cycle_triggers
end

function calc:_watch_key(sn, input, prop)
	local prop = prop or 'value'
	return sn.."/"..input.."/"..prop
end

function calc:_add_watch(trigger, input)
	assert(input.sn and input.input and input.prop)

	local key = self:_watch_key(input.sn, input.input, input.prop)
	input._key = key

	local triggers = self._watch_map[key] or {}

	table.insert(triggers, trigger)
	self._watch_map[key] = triggers

	local device = self._api:get_device(input.sn)
	if not device then
		return 
	end

	local value, timestamp, quality = device:get_input_prop(input.input, input.prop)
	if value ~= nil and ( quality == nil or quality == 0 ) then
		input.value = value
		input.timestamp = timestamp
	end
end

function calc:_complete_trigger(trigger)
	local inputs = trigger.inputs
	local values = {}
	for _, v in ipairs(inputs) do
		local val = v.value or v.default
		if not val then
			self._log:trace("Missing input", self:_watch_key(v.sn, v.input, v.prop))
			return nil, "missing input"
		end
		table.insert(values, val)
	end
	self._log:trace("Ready for trigger", trigger.name)
	return self:_complete_call(trigger, table.unpack(values))
end

function calc:_complete_call(trigger, ...)
	local f= trigger.callback
	assert(f)

	local r, er, err = xpcall(f, debug.traceback, ...)
	if not r then
		self._log:warning('Calc Callback bug', er, err)
		return nil, er and tostring(er) or nil
	end
	return er, er and tostring(err) or nil
end

function calc:_clean_watch(key)
	local triggers = self._watch_map[key] or {}

	for _, trigger in ipairs(triggers) do
		for _, input in ipairs(trigger.inputs) do
			if key == input._key then
				self._log:trace("Clean input value", key, trigger.name)
				input.value = nil
				input.timestamp = nil
			end
		end
	end
end

function calc:_on_add_device(app_src, sn, props)
	--[[
	local inputs = props.inputs or {}
	for _, v in ipairs(inputs) do
		local key = sn.."/"..input.."/"
		for k, v in ipairs(self._watch_map) do
			if k == key then
				-- TODO:
			end
		end
	end
	]]--
end

function calc:_on_del_device(app_src, sn)
	for k, v in ipairs(self._watch_map) do
		if k:sub(1, len) == key then
			self._log:trace("Clean device input", key)
			self:_clean_watch(key)
		end
	end
end

function calc:_on_mod_device(app_src, sn, props)
	self:_on_del_device(app_src, sn)
	self:_on_add_device(app_src, sn, props)
end

function calc:_on_input(app_src, sn, input, prop, value, timestamp, quality)
	local key = self:_watch_key(sn, input, prop)

	if not self._watch_map[key] then
		--self._log:trace("Skip none watched value", app_src, sn, input, prop, value, timestamp, quality)
		return
	end

	if self._cov then
		-- If cov enabled
		--self._log:trace("COV push watched value", key, value, timestamp, quality)
		return self._cov:handle(key, value, timestamp, quality)
	end

	return self:_on_cov_input(key, value, timestamp, quality)
end

function calc:_on_cov_input(key, value, timestamp, quality)
	self._log:trace("Value changed for watched key: "..key, value, timestamp, quality)
	local triggers = self._watch_map[key] or {}

	for _, trigger in ipairs(triggers) do
		for _, input in ipairs(trigger.inputs) do
			if key == input._key then
				if quality == nil or quality == 0 then
					input.value = value
					input.timestamp = timestamp
				else
					input.value = nil
					input.timestamp = nil
				end
			end
		end
		self:_complete_trigger(trigger)
	end
end

local function create_handler(calc)
	local calc = calc
	return {
		--- 处理设备对象添加消息
		on_add_device = function(app_src, sn, props)
			--- 获取对象目录
			calc:_on_add_device(app_src, sn, props)
		end,
		--- 处理设备对象删除消息
		on_del_device = function(app_src, sn)
			calc:_on_del_device(app_src, sn)
		end,
		--- 处理设备对象修改消息
		on_mod_device = function(app_src, sn, props)
			calc:_on_mod_device(app_src, sn, props)
		end,
		--- 处理设备输入项数值变更消息
		on_input = function(app_src, sn, input, prop, value, timestamp, quality)
			calc:_on_input(app_src, sn, input, prop, value, timestamp, quality)
		end
	}
end

function calc:_map_handler_func(handler, calc_handler, func)
	local hf = handler[func] or function() end
	local calc_func = calc_handler[func]
	local map_f = function(...)
		local r, er, err = xpcall(calc_func, debug.traceback, ...)
		if not r then
			self._log:warning('Calc bug:', er, err)
		end
		return hf(...)
	end
	handler[func] = map_f
end

function calc:_map_handler(handler)
	assert(self._cov, "Calc util needs to be started and then map handler")
	local calc_handler = create_handler(self)
	self:_map_handler_func(handler, calc_handler, 'on_add_device')
	self:_map_handler_func(handler, calc_handler, 'on_del_device')
	self:_map_handler_func(handler, calc_handler, 'on_mod_device')
	self:_map_handler_func(handler, calc_handler, 'on_input')
	return handler
end

function calc:start(handler)
	assert(handler, "Calc util need the api handler")
	self._cov = cov:new(function(...)
		self:_on_cov_input(...)
	end)
	self._cov:start()

	self._sys:fork(function()
		while not self._stop do
			local now = ioe.time()
			for name, trigger in pairs(self._cycle_triggers) do
				local cycle = trigger.cycle
				if cycle and cycle.next_time <= now then
					self:_complete_trigger(trigger)
					cycle.next_time = cycle.next_time + cycle.cycle_time
				end
			end

			self._sys:sleep(1000)
		end

		self._log:trace("Stop COV before quit trigger")
		if self._cov then
			self._cov:stop()
			self._cov = nil
		end
		self._sys:wakeup(self)
	end)
	return self:_map_handler(handler)
end

function calc:stop()
	if not self._stop then
		self._stop = true
		self._sys:wait(self)
	end
end


return calc
