---
-- 计算触发器模块
--
-- 本模块提供基于输入值变化触发回调的计算引擎，
-- 支持周期性执行。
---

local class = require 'middleclass'
local ioe = require 'ioe'
local cov = require 'cov'

---
-- 计算触发器类
--
-- 监控设备输入并在值变化时或周期性间隔时触发回调。
---
local calc = class("APP_UTILS_CALC")

---
-- 初始化计算触发器引擎
-- @param sys: 系统API对象
-- @param api: 数据API对象
-- @param logger: 日志记录器实例
---
function calc:initialize(sys, api, logger)
	self._sys = sys
	self._api = api
	self._log = logger
	self._triggers = {} --- 所有触发器，按触发器名称索引
	self._watch_map = {}  -- 键为: sn/input/prop
	self._cycle_triggers = {} -- 按触发器名称索引
	self._cov = nil
end

---
-- 添加一个监控设备输入的触发器，在变化时触发回调
-- @param name: 唯一的触发器名称
-- @param inputs: 输入规范数组 {sn, input, prop, default}
-- @param trigger_cb: 回调函数(trigger_values...)
-- @param cycle_time: 可选的周期性触发周期时间（秒）
-- @return: 手动触发回调的函数
---
function calc:add(name, inputs, trigger_cb, cycle_time)
	assert(self._triggers[name] == nil, "Trigger "..name.." already exists!")
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

---
-- 按名称移除触发器
-- @param name: 要移除的触发器名称
---
function calc:remove(name)
	self._triggers[name] = nil
	-- TODO: 清理watch_map和_cycle_triggers
end

---
-- 为设备输入生成监控键
-- @param sn: 设备序列号
-- @param input: 输入名称
-- @param prop: 属性名称
-- @return: 监控键字符串
---
function calc:_watch_key(sn, input, prop)
	local prop = prop or 'value'
	return sn.."/"..input.."/"..prop
end

---
-- 为设备输入添加监控
-- @param trigger: 触发器对象
-- @param input: 输入规范
---
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

---
-- 使用当前输入值完成触发器执行
-- @param trigger: 触发器对象
-- @return: 回调结果或nil、失败时的错误信息
---
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

---
-- 带错误保护执行触发器回调
-- @param trigger: 触发器对象
-- @param ...: 回调参数
-- @return: 回调结果或nil、失败时的错误信息
---
function calc:_complete_call(trigger, ...)
	local f= trigger.callback
	assert(f)

	local r, er, err = xpcall(f, debug.traceback, ...)
	if not r then
		self._log:warning("Calc's callback code error:", er, err)
		return nil, er and tostring(er) or nil
	end
	return er, er and tostring(err) or nil
end

---
-- 清理监控某个键的所有触发器的输入值
-- @param key: 监控键字符串
---
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

---
-- 处理设备添加事件
-- @param app_src: 源应用名称
-- @param sn: 设备序列号
-- @param props: 设备属性
---
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

---
-- 处理设备删除事件
-- @param app_src: 源应用名称
-- @param sn: 设备序列号
---
function calc:_on_del_device(app_src, sn)
	for k, v in ipairs(self._watch_map) do
		if k:sub(1, len) == key then
			self._log:trace("Clean device input", key)
			self:_clean_watch(key)
		end
	end
end

---
-- 处理设备修改事件
-- @param app_src: 源应用名称
-- @param sn: 设备序列号
-- @param props: 设备属性
---
function calc:_on_mod_device(app_src, sn, props)
	self:_on_del_device(app_src, sn)
	self:_on_add_device(app_src, sn, props)
end

---
-- 处理输入值变化事件
-- @param app_src: 源应用名称
-- @param sn: 设备序列号
-- @param input: 输入名称
-- @param prop: 属性名称
-- @param value: 新值
-- @param timestamp: 值时间戳
-- @param quality: 质量标志
---
function calc:_on_input(app_src, sn, input, prop, value, timestamp, quality)
	local key = self:_watch_key(sn, input, prop)

	if not self._watch_map[key] then
		--self._log:trace("Skip none watched value", app_src, sn, input, prop, value, timestamp, quality)
		return
	end

	if self._cov then
		-- 如果启用了COV
		--self._log:trace("COV push watched value", key, value, timestamp, quality)
		return self._cov:handle(key, value, timestamp, quality)
	end

	return self:_on_cov_input(key, value, timestamp, quality)
end

---
-- 处理COV（值变化）输入事件
-- 更新监控变化输入的所有触发器
-- @param key: 监控键字符串
-- @param value: 新值
-- @param timestamp: 值时间戳
-- @param quality: 质量标志
---
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

---
-- 为设备和输入事件创建处理程序表
-- @param calc: 计算引擎实例
-- @return: 带回调函数的处理程序表
---
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
		on_input_batch = function(app_src, sn, datas)
			for k, v in ipairs(datas) do
				calc:_on_input(app_src, sn, table.unpack(v))
			end
		end
	}
end

---
-- 将计算处理程序函数映射到用户处理程序，带错误保护
-- @param handler: 用户的处理程序表
-- @param calc_handler: 计算器的处理程序表
-- @param func: 要映射的函数名称
---
function calc:_map_handler_func(handler, calc_handler, func)
	local hf = handler[func] or function() end
	local calc_func = calc_handler[func]
	local map_f = function(...)
		local r, er, err = xpcall(calc_func, debug.traceback, ...)
		if not r then
			self._log:warning('Calc handler function code error:', er, err)
		end
		return hf(...)
	end
	handler[func] = map_f
end

---
-- 将计算器处理程序映射到用户的处理程序表
-- @param handler: 要扩展的用户处理程序表
-- @return: 扩展后的处理程序表
---
function calc:_map_handler(handler)
	assert(self._cov, "Calc util needs to be started and then map handler")
	local calc_handler = create_handler(self)
	self:_map_handler_func(handler, calc_handler, 'on_add_device')
	self:_map_handler_func(handler, calc_handler, 'on_del_device')
	self:_map_handler_func(handler, calc_handler, 'on_mod_device')
	self:_map_handler_func(handler, calc_handler, 'on_input')
	return handler
end

---
-- 启动计算引擎
-- 启动COV监控和周期触发器循环
-- @param handler: 要用计算器处理程序扩展的处理程序表
-- @return: 扩展后的处理程序表
---
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

---
-- 停止计算引擎
-- 停止COV监控和周期触发器循环
---
function calc:stop()
	if not self._stop then
		self._stop = true
		self._sys:wait(self)
	end
end


return calc
