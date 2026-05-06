---
-- 设备API模块
--
-- 本模块为应用提供设备管理接口。
-- 设备代表I/O点、通信通道或数据源，
-- 应用可以创建、管理和与之交互。
---

local skynet = require 'skynet'
local ioe = require 'ioe'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local stat_api = require 'app.stat'

---
-- 设备API类
--
-- 表示具有输入、输出和命令的设备实例。
-- 提供数据处理、通信转储和设备管理的方法。
---
local device = class("APP_MGR_DEV_API")

---
-- 启用新的批量更新模式
-- 启用后，输入更新将被批量处理并定期发布，
-- 而不是立即发布，以提高性能。
---
local USE_NEW_BATCH_UPDATE = 1

---
-- 初始化设备实例
-- @param api: 父API对象
-- @param sn: 设备序列号
-- @param props: 设备属性表
--   - name: 设备名称
--   - desc: 设备描述
--   - inputs: 输入定义数组 {name, desc, unit}
--   - outputs: 输出定义数组
--   - commands: 命令定义数组
-- @param guest: 如果为true则表示这是一个访客（只读）设备
-- @param secret: 设备密钥
---
--- 不要直接调用此函数，而是通过api.lua调用
function device:initialize(api, sn, props, guest, secret)
	self._api = api
	self._logger = api._logger
	self._sn = sn
	self._props = props
	self._app_src = api._app_name
	self._secret = secret
	if guest then
		self._app_name = dc.get('DEV_IN_APP', sn) or api._app_name
		self._props = dc.get('DEVICES', sn) or {}
	else
		self._app_name = api._app_name
	end
	self._data_chn = api._data_chn
	self._ctrl_chn = api._ctrl_chn
	self._comm_chn = api._comm_chn
	self._event_chn = api._event_chn
	self._guest = guest

	self._inputs_map = {}
	for _, t in ipairs(props.inputs or {}) do
		assert(self._inputs_map[t.name] == nil, "Duplicated input name ["..t.name.."] found")
		self._inputs_map[t.name] = t
	end
	self._stats = {}

	if not guest then
		dc.set('DEVICES', sn, props)
		dc.set('DEV_IN_APP', sn, self._app_name)
	end

	if USE_NEW_BATCH_UPDATE then
		self._data_cache_map = {}
		self._data_cache_map_token = {}
		skynet.fork(function()
			while not self._close_wait do
				skynet.sleep(300, self._data_cache_map_token)
				if #self._data_cache_map > 0 then
					skynet.sleep(5) -- 等待更多数据到来
					local data = self._data_cache_map
					self._data_cache_map = {}
					self._data_chn:publish('input_batch', self._app_name, self._sn, data)
				end
			end
			skynet.wakeup(self._close_wait)
		end)
	end
end

---
-- 内部清理设备引用
-- 清除所有内部引用以允许垃圾回收
---
function device:_cleanup()
	self._guest = true
	self._app_name = nil
	self._app_src = nil
	self._sn = nil
	self._props = nil
	self._inputs_map = nil
	self._data_chn = nil
	self._ctrl_chn = nil
	self._comm_chn = nil
	self._api = nil
	self._cov = nil
end

---
-- 清理并从系统中删除设备
-- 停止所有服务，从数据中心删除设备，发布删除事件
---
function device:cleanup()
	if self._guest then
		return
	end
	if USE_NEW_BATCH_UPDATE and self._data_cache_map_token then
		self._close_wait = {}
		-- 唤醒只是标记此令牌将被唤醒
		skynet.wakeup(self._data_cache_map_token)
		skynet.sleep(200, self._close_wait)
	end

	if self._cov then
		self._cov:stop()
	end
	for _, s in ipairs(self._stats) do
		s:cleanup()
	end
	self._stats = {}

	local sn = self._sn
	local props = self._props

	self._api._devices[sn] = nil

	dc.set('DEVICES', sn, nil)
	dc.set('DEV_IN_APP', sn, nil)
	dc.set('INPUT', sn, nil)
	dc.set('OUTPUT', sn, nil)

	self._logger:trace("DELETE DEVICE", self._app_name, sn, props)
	self._data_chn:publish('del_device', self._app_name, sn, props)

	self:_cleanup()
end

---
-- 验证属性名称格式
-- @param name: 属性名称字符串
-- @return: 如果有效返回true（仅包含单词字符和下划线）
---
local function valid_prop_name(name)
	return nil == string.find(name, "[^%w_]")
end

---
-- 修改设备输入、输出和命令
-- 用新定义替换现有定义
-- @param inputs: 输入定义数组 {name, desc, unit}
-- @param outputs: 输出定义数组
-- @param commands: 命令定义数组
-- @return: 成功返回true
---
function device:mod(inputs, outputs, commands)
	assert(not self._guest, "Device permission denied!")
	for _, v in ipairs(inputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid input name") end
	for _, v in ipairs(outputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid output name") end
	for _, v in ipairs(commands or {}) do assert(valid_prop_name(v.name), v.name.." is not valid command name") end

	self._props.inputs = inputs or self._props.inputs
	self._props.outputs = outputs or self._props.outputs
	self._props.commands = commands or self._props.commands

	self._inputs_map = {}
	for _, t in ipairs(inputs or {}) do
		self._inputs_map[t.name] = t
	end
	dc.set('DEVICES', self._sn, self._props)
	if self._cov then
		self._cov:clean()
	end

	self._data_chn:publish('mod_device', self._app_name, self._sn, self._props)
	return true
end

---
-- 向现有设备添加新输入、输出和命令
-- 追加到现有定义而不是替换
-- @param inputs: 要添加的输入定义数组
-- @param outputs: 要添加的输出定义数组
-- @param commands: 要添加的命令定义数组
---
function device:add(inputs, outputs, commands)
	assert(not self._guest, "Device permission denied!")
	for _, v in ipairs(inputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid input name") end
	for _, v in ipairs(outputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid output name") end
	for _, v in ipairs(commands or {}) do assert(valid_prop_name(v.name), v.name.." is not valid command name") end

	local org_inputs = self._props.inputs
	for _, v in ipairs(inputs or {}) do
		org_inputs[#org_inputs + 1] = v
	end
	local org_outputs = self._props.outputs
	for _, v in ipairs(outputs or {}) do
		org_outputs[#org_outputs + 1] = v
	end
	local org_commands = self._props.commands
	for _, v in ipairs(commands or {}) do
		org_commands[#org_commands + 1] = v
	end
	self:mod(org_inputs, org_outputs, org_commands)
end

---
-- 从数据中心获取输入属性值
-- @param input: 输入名称
-- @param prop: 属性名称（value、timestamp、quality）
-- @return: value、timestamp、quality，未找到返回nil
---
function device:get_input_prop(input, prop)
	local t = dc.get('INPUT', self._sn, input, prop)
	if t then
		return t.value, t.timestamp, t.quality
	end
end

---
-- 内部方法：将输入值发布到数据通道
-- 如果启用批量模式则使用批量模式，否则立即发布
-- @param input: 输入名称
-- @param prop: 属性名称
-- @param value: 属性值
-- @param timestamp: 值时间戳
-- @param quality: 值质量标志
---
function device:_publish_input(input, prop, value, timestamp, quality)
	assert(timestamp)
	if not USE_NEW_BATCH_UPDATE then
		return self._data_chn:publish('input', self._app_name, self._sn, input, prop, value, timestamp, quality)
	end
	--- 数据触发的新模式
	self._data_cache_map[#self._data_cache_map + 1] = { input, prop, value, timestamp, quality }
	skynet.wakeup(self._data_cache_map_token)
end

---
-- 批量设置多个输入属性
-- 接受表格式 {input, prop, value, timestamp, quality}
-- 或对象格式 {{input=, prop=, value=, timestamp=, quality=}, ...}
-- @param ...: 输入数据的可变参数
-- @return: 成功返回true，失败返回nil和错误信息
---
function device:set_input_prop_batch(...)
	local inputs = {...}
	if #inputs == 0 then
		return nil, 'No input data'
	end

	if inputs[1].input then
		local map_inputs = {}
		for _, v in ipairs(inputs) do
			map_inputs[#map_inputs + 1] = {v.input, v.prop, v.value, v.timestamp or ioe.time(), v.quality or 0 }
		end
		inputs = map_inputs
	else
		for _, v in ipairs(inputs) do
			inputs[4] = inputs[4] or ioe.time()
			inputs[5] = inputs[5] or 0
		end
	end

	if self._cov then
		local changed_inputs = self._cov:handle_batch(inputs)
		if #changed_inputs == 0 then
			return true -- 所有输入数据未变化
		end
		inputs = changed_inputs
	end

	-- 将inputs复制到缓存映射中然后唤醒data_cache_map_token
	table.move(inputs, 1, #inputs, #self._data_cache_map + 1, #self._data_cache_map)
	skynet.wakeup(self._data_cache_map_token)
	-- TODO: 我们应该在这里sleep吗？

	return true
end

---
-- 设置单个输入属性值
-- 验证输入名称并根据输入定义执行类型转换
-- @param input: 输入名称
-- @param prop: 属性名称（通常为'value'）
-- @param value: 属性值
-- @param timestamp: 可选时间戳（默认为当前时间）
-- @param quality: 可选质量标志（默认为0）
-- @return: 成功返回true，失败返回nil和错误信息
---
function device:set_input_prop(input, prop, value, timestamp, quality)
	assert(input and prop and (value ~= nil), "Input/Prop/Value are required as not nil value")
	if self._guest then
		assert(self._secret, "Device permission denied!")
		local secret = dc.get("DEVICE_SECRET", self._sn)
		assert(secret, "Device permission denied!")
		assert(secret == self._secret, "Device secret is not correct")
	end

	local value = value
	if type(value) == 'boolean' then
		value = value and 1 or 0
	end

	local it = self._inputs_map[input]
	if not it then
		return nil, "Property "..input.." does not exist in device "..self._sn
	else
		if prop == 'value' then
			if it.vt == 'int' then
				value = math.floor(tonumber(value))
			elseif it.vt == 'string' then
				value = tostring(value)
			else
				value = tonumber(value)
			end
		end
	end
	if not value then
		return nil, "Invalid value"
	end

	local timestamp = timestamp or ioe.time()
	local quality = quality or 0

	dc.set('INPUT', self._sn, input, prop, {value=value, timestamp=timestamp, quality=quality})
	if not self._cov then
		self:_publish_input(input, prop, value, timestamp, quality)
	else
		self._cov:handle(input..'/'..prop, value, timestamp, quality)
	end
	return true
end

---
-- 设置带紧急标志的输入属性值
-- 在设置值之前发布紧急事件
-- @param input: 输入名称
-- @param prop: 属性名称
-- @param value: 属性值
-- @param timestamp: 可选时间戳
-- @param quality: 可选质量标志
-- @return: 成功返回true，失败返回nil和错误信息
---
function device:set_input_prop_emergency(input, prop, value, timestamp, quality)
	assert(input and prop and value, "Input/Prop/Value are required as not nil value")
	if self._guest then
		assert(self._secret, "Device permission denied!")
		local secret = dc.get("DEVICE_SECRET", self._sn)
		assert(secret, "Device permission denied!")
		assert(secret == self._secret, "Device secret is not correct")
	end

	local value = value
	local it = self._inputs_map[input]
	if not it then
		return nil, "Property "..input.." does not exist in device "..self._sn
	else
		if prop == 'value' then
			if it.vt == 'int' then
				value = math.floor(tonumber(value))
			elseif it.vt == 'string' then
				value = tostring(value)
			else
				value = tonumber(value)
			end
		end
	end
	if not value then
		return nil, "Invalid value"
	end

	local timestamp = timestamp or ioe.time()
	local quality = quality or 0

	self._data_chn:publish('input_em', self._app_name, self._sn, input, prop, value, timestamp, quality)

	return self:set_input_prop(input, prop, value, timestamp, quality)
end

---
-- 从数据中心获取输出属性值
-- @param output: 输出名称
-- @param prop: 属性名称
-- @return: value、timestamp
---
function device:get_output_prop(output, prop)
	local t = dc.get('OUTPUT', self._sn, output, prop)
	return t.value, t.timestamp
end

---
-- 设置输出属性值
-- 发布到控制通道供应用处理
-- @param output: 输出名称
-- @param prop: 属性名称
-- @param value: 属性值
-- @param timestamp: 可选时间戳
-- @param priv: 用于结果关联的可选私有数据
-- @return: 成功返回true，失败返回nil和错误信息
---
function device:set_output_prop(output, prop, value, timestamp, priv)
	local priv = priv or '__NO_RESULT__CALL__'
	for _, v in ipairs(self._props.outputs or {}) do
		if v.name == output then
			local timestamp = timestamp or ioe.time()
			dc.set('OUTPUT', self._sn, output, prop, {value=value, timestamp=timestamp})
			self._ctrl_chn:publish('output', self._app_src, self._app_name, self._sn, output, prop, value, timestamp, priv)
			return true
		end
	end
	return nil, "Output property "..output.." does not exist in device "..self._sn
end

---
-- 向设备发送命令
-- 发布到控制通道供应用处理
-- @param command: 命令名称
-- @param param: 命令参数
-- @param priv: 用于结果关联的可选私有数据
-- @return: 成功返回true，失败返回nil和错误信息
---
function device:send_command(command, param, priv)
	local priv = priv or '__NO_RESULT__CALL__'
	for _, v in ipairs(self._props.commands or {}) do
		if v.name == command then
			self._ctrl_chn:publish("command", self._app_src, self._app_name, self._sn, command, param, priv)
			return true
		end
	end
	return nil, "Command "..command.." does not exist in device "..self._sn
end

---
-- 获取设备序列号
-- @return: 设备序列号字符串
---
function device:sn()
	return self._sn
end

---
-- 获取创建此设备的应用实例名称
-- @return: 应用名称
---
function device:app_name()
	return self._app_name
end

---
-- 获取设备属性表
-- @return: 包含设备元数据、输入、输出、命令的表
---
function device:list_props()
	return self._props
end

---
-- 列出所有输入值并传递给回调
-- @param data_cb: 回调函数(input, prop, value, timestamp, quality)
---
function device:list_inputs(data_cb)
	local inputs = self._props.inputs or {}
	local input_vals = dc.get('INPUT', self._sn) or {}
	for _, v in ipairs(inputs) do
		for prop, val in pairs(input_vals[v.name] or {}) do
			data_cb(v.name, prop, val.value, val.timestamp, val.quality)
		end
	end
end

---
-- 为输入配置值变化（COV）监控
-- 启用后，仅发布实际发生变化的输入值
-- @param opt: COV选项表，nil表示禁用
---
function device:cov(opt)
	assert(not self._guest, "Device permission denied!")
	if not opt then
		self._cov = nil
	else
		local COV = require 'cov'

		self._cov = COV:new(function(key, value, timestamp, quality)
			local input, prop = string.match(key, '^(.+)/([^/]+)')
			assert(input and prop, "Bug found matching input/prop key")
			return self:_publish_input(input, prop, value, timestamp, quality)
		end, opt)

		self._cov:start()
	end
end

---
-- 获取此设备的所有输入数据
-- @return: 来自数据中心的输入值表
---
function device:data()
	return dc.get('INPUT', self._sn)
end

---
-- 将所有输入数据刷新到数据通道
-- 强制立即发布所有当前输入值
---
function device:flush_data()
	assert(not self._guest, "Device permission denied!")
	return self:list_inputs(function(input, prop, value, timestamp, quality)
		self._data_chn:publish('input', self._app_name, self._sn, input, prop, value, timestamp, quality)
	end)
end

---
-- 将通信数据转储到通信通道
-- @param dir: 方向（send/recv）
-- @param ...: 通信数据
-- @return: 发布结果
---
function device:dump_comm(dir, ...)
	assert(not self._guest, "Device permission denied!")
	return self._comm_chn:publish(self._app_name, self._sn, dir, ioe.time(), ...)
end

---
-- 为此设备触发事件
-- @param level: 事件严重性级别
-- @param type_: 事件类型字符串
-- @param info: 事件描述
-- @param data: 可选的事件数据表
-- @param timestamp: 可选的事件时间戳
-- @return: 事件触发结果
---
function device:fire_event(level, type_, info, data, timestamp)
	assert(not self._guest, "Device permission denied!")
	return self._api:_fire_event(self._sn, level, type_, info, data, timestamp)
end

---
-- 为此设备创建统计计数器
-- @param name: 统计名称（例如packets_in、bytes_out）
-- @return: 统计对象
---
function device:stat(name)
	-- assert(not self._guest, "Device permission denied!")
	local stat = stat_api:new(self._api, self._sn, name, self._guest)
	self._stats[#self._stats + 1] = stat
	return stat
end

---
-- 使用密钥与其他应用共享此设备
-- 拥有正确密钥的应用可以向此设备写入输入值
-- @param secret: 密钥字符串，nil表示禁用共享
---
function device:share(secret)
	self._secret = secret
	dc.set('DEVICE_SECRET', self._secret)
end

return device
