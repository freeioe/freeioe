--- 应用API模块
--
-- 本模块为FreeIOE应用提供核心API接口
-- 管理设备生命周期，处理数据/控制/通信分发，并提供与应用管理器的集成
---

local skynet = require 'skynet'
local snax = require 'skynet.snax'
local ioe = require 'ioe'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'
local dev_api = require 'app.device'
local app_event = require 'app.event'
local app_logger = require 'app.logger'
local threshold_buffer = require 'buffer.threshold'

---
-- 应用API类
--
-- 提供应用与FreeIOE系统服务交互的主要接口，
-- 包括设备管理、数据处理和事件处理。
---
local api = class("APP_MGR_API")

---
-- 初始化API实例
-- @param app_name: 应用名称
-- @param mgr_snax: appmgr服务句柄（可选，为nil时将查询）
-- @param logger: 日志记录器实例（可选，为nil时创建默认实例）
---
function api:initialize(app_name, mgr_snax, logger)
	self._app_name = app_name
	self._mgr_snax = mgr_snax or snax.queryservice('appmgr')
	self._devices = {}
	self._event_fire_buf = nil
	self._logger = logger or app_logger:new(app_name)
end

---
-- 清理API资源
-- 删除所有设备并关闭处理程序
---
function api:cleanup()
	self:close_handler()
	for sn, dev in pairs(self._devices) do
		self:del_device(dev)
	end
	self._devices = {}
end

---
-- 将批量输入数据拆分为单独的调用
-- @param f: 处理器函数
-- @param app: 应用名称
-- @param sn: 设备序列号
-- @param datas: 数据批次表
-- @return: true
---
function api:input_batch_split(f, app, sn, datas)
	for _, v in ipairs(datas) do
		f(app, sn, table.unpack(v))
	end
	return true
end

---
-- 将数据通道消息分发到相应的处理程序
-- @param channel: 通道名称
-- @param source: 消息源
-- @param cmd: 命令类型（input、output、command、input_batch）
-- @param app: 应用名称
-- @param ...: 附加参数
-- @return: 处理程序结果，未找到处理程序返回nil
---
function api:data_dispatch(channel, source, cmd, app, ...)
	-- self._logger:trace('Data Dispatch', channel, source, cmd, app, ...)
	local f = self._handler['on_'..cmd]
	if f then
		return f(app, ...)
	else
		if cmd == 'input_batch' then
			-- self._logger:trace('Data Batch Dispatch', channel, source, cmd, app, 'fallback to on_input')
			local f = self._handler['on_input']
			if f then
				return self:input_batch_split(f, app, ...)
			end
		end
		self._logger:trace('No handler for '..cmd)
	end
end

---
-- 将控制通道消息分发到相应的处理程序
-- 处理同步命令并自动发布结果
-- @param channel: 通道名称
-- @param source: 消息源
-- @param ctrl: 控制命令类型
-- @param app_src: 源应用
-- @param app: 目标应用
-- @param ...: 命令参数
---
function api:ctrl_dispatch(channel, source, ctrl, app_src, app, ...)
	if app ~= self._app_name then
		--- 跳过目标是其他应用的请求
		return
	end

	self._logger:trace('Ctrl Dispatch', channel, source, ctrl, app_src, app, ...)
	local f = self._handler['on_'..ctrl]
	if f then
		--- 检查是否为结果分发
		if string.match(ctrl, '(.+)_result$') then
			skynet.fork(function(...)
				f(app_src, ...)
			end, ...)

			return
		end

		--- priv是最后一个参数
		local priv = select(-1, ...)

		--- 创建一个新协程来执行command/output/ctrl并等待结果
		skynet.fork(function(...)
			local results = table.pack(xpcall(f, debug.traceback, app_src, ...))
			if not results[1] then
				self._ctrl_chn:publish(ctrl..'_result', app, app_src, priv, false, results[2])
			else
				if results[2] == nil then
					-- Table unpack丢失nil返回
					results[2] = false
				end
				self._ctrl_chn:publish(ctrl..'_result', app, app_src, priv, table.unpack(results, 2))
			end
		end, ...)
	else
		self._logger:trace('No handler for '..ctrl)
	end
end

---
-- 将通信数据分发到处理程序
-- @param channel: 通道名称
-- @param source: 消息源
-- @param app: 应用名称
-- @param ...: 通信数据
---
function api:comm_dispatch(channel, source, app, ...)
	--self._logger:trace('Comm Dispatch', channel, source, ...)
	local f = self._handler.on_comm
	if f then
		return f(app, ...)
	else
		self._logger:trace('No handler for on_comm')
	end
end

---
-- 将统计数据分发到处理程序
-- @param channel: 通道名称
-- @param source: 消息源
-- @param app: 应用名称
-- @param ...: 统计数据
---
function api:stat_dispatch(channel, source, app, ...)
	--self._logger:trace('Stat Dispatch', channel, source, ...)
	local f = self._handler.on_stat
	if f then
		return f(app, ...)
	else
		self._logger:trace('No handler for on_stat')
	end
end

---
-- 将事件数据分发到处理程序
-- @param channel: 通道名称
-- @param source: 消息源
-- @param app: 应用名称
-- @param ...: 事件数据
---
function api:event_dispatch(channel, source, app, ...)
	--self._logger:trace('Event Dispatch', channel, source, ...)
	local f = self._handler.on_event
	if f then
		return f(app, ...)
	else
		self._logger:trace('No handler for on_event')
	end
end

---
-- 关闭所有多播通道并清理处理程序
---
function api:close_handler()
	if self._data_chn then
		self._data_chn:unsubscribe()
		self._data_chn = nil
	end
	if self._ctrl_chn then
		self._ctrl_chn:unsubscribe()
		self._ctrl_chn = nil
	end
	if self._comm_chn then
		self._comm_chn:unsubscribe()
		self._comm_chn = nil
	end
	if self._stat_chn then
		self._stat_chn:unsubscribe()
		self._stat_chn = nil
	end
	if self._event_chn then
		self._event_chn:unsubscribe()
		self._event_chn = nil
	end
end

---
-- 为应用回调设置处理程序并订阅通道
-- @param handler: 包含回调函数的表（on_input、on_output、on_command等）
-- @param watch_data: 布尔值，如果为true则订阅数据通道以监视所有设备数据
---
function api:set_handler(handler, watch_data)
	self._handler = handler
	if not self._handler then
		return api:close_handler()
	end

	local mgr = self._mgr_snax

	self._data_chn = self._data_chn or mc.new ({
		channel = mgr.req.get_channel('data'),
		dispatch = function(channel, source, ...)
			self:data_dispatch(channel, source, ...)
		end
	})
	if watch_data then
		self._data_chn:subscribe()
	end

	self._ctrl_chn = self._ctrl_chn or mc.new ({
		channel = mgr.req.get_channel('ctrl'),
		dispatch = function(channel, source, ...)
			self:ctrl_dispatch(channel, source, ...)
		end
	})
	if handler.on_ctrl or handler.on_output or handler.on_command or
		handler.on_ctrl_result or handler.on_output_result or handler.on_command_result then

		self._ctrl_chn:subscribe()
	end

	self._comm_chn = self._comm_chn or mc.new ({
		channel = mgr.req.get_channel('comm'),
		dispatch = function(channel, source, ...)
			self:comm_dispatch(channel, source, ...)
		end
	})
	if handler.on_comm then
		self._comm_chn:subscribe()
	end

	self._stat_chn = self._stat_chn or mc.new({
		channel = mgr.req.get_channel('stat'),
		dispatch = function(channel, source, ...)
			self:stat_dispatch(channel, source, ...)
		end
	})
	if handler.on_stat then
		self._stat_chn:subscribe()
	end

	self._event_chn = self._event_chn or mc.new({
		channel = mgr.req.get_channel('event'),
		dispatch = function(channel, source, ...)
			self:event_dispatch(channel, source, ...)
		end
	})
	if handler.on_event then
		self._event_chn:subscribe()
	end
	self:_set_event_threshold(20)
end

---
-- 列出系统中的所有设备
-- @param with_data: 布尔值，如果为true则包含当前输入/输出值
-- @return: 设备表，可选择包含数据值
---
function api:list_devices(with_data)
	local devs = dc.get('DEVICES')
	if not with_data then
		return devs
	end

	-- 获取dc快照
	local inputs = dc.get('INPUT') or {}
	local outputs = dc.get('OUTPUT') or {}
	local dev_in_apps = dc.get('DEV_IN_APP') or {}

	for sn, props in pairs(devs or {}) do
		props.app_name = dev_in_apps[sn]

		local vals = inputs[sn] or {}
		for _, input in ipairs(props.inputs or {}) do
			input.props = vals[input.name]
		end
		local ovals = outputs[sn] or {}
		for _, output in ipairs(props.outputs or {}) do
			output.props = ovals[output.name]
		end
	end
	-- 返回所有设备及其数据
	return devs
end

---
-- 验证设备元数据表
-- @param meta: 包含设备元数据的表
-- @raises: 如果缺少必填字段则断言错误
---
function valid_device_meta(meta)
	local meta_assert = function(name)
		assert(meta[name], "Device "..name.." is required in meta info!")
	end
	assert(meta, 'Device meta is required!')
	meta_assert("name")
	meta_assert("description")
	meta_assert("manufacturer")
	meta_assert("series")
	meta_assert("link")
end

---
-- 获取默认设备元数据模板
-- @return: 包含默认设备元数据字段的表
---
function api:default_meta()
	return {
		name = "Unknown",
		description = "Unknown device",
		manufacturer = "FreeIOE",
		series = "Unknown",
		link = "http://device.freeioe.org/device?name=",
	}
end

---
-- 验证设备序列号格式
-- @param sn: 设备序列号字符串
-- @return: 如果有效返回true，如果包含无效字符返回false
---
local function valid_device_sn(sn)
	--return nil == string.find(sn, '%s')
	return nil == string.find(sn, "[^%w_%-%.]")
end

---
-- 验证属性/输入/输出名称格式
-- @param name: 属性名称字符串
-- @return: 如果有效返回true，如果包含无效字符返回false
---
local function valid_prop_name(name)
	return nil == string.find(name, "[^%w_]")
end

---
-- 向应用添加新设备
-- @param sn: 设备序列号（唯一标识符）
-- @param meta: 设备元数据表（name、description、manufacturer、series、link）
-- @param inputs: 输入定义数组 {name, desc, unit}
-- @param outputs: 输出定义数组 {name, desc, unit}
-- @param commands: 命令定义数组 {name, desc}
-- @return: 用于访问设备的设备对象
---
function api:add_device(sn, meta, inputs, outputs, commands)
	assert(self._handler, "Cannot add device before initialize your API handler by calling set_handler")
	assert(sn and meta, "Device Serial Number and Meta Information is required!")
	assert(valid_device_sn(sn), "Invalid sn: "..sn)
	for _, v in ipairs(inputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid input name") end
	for _, v in ipairs(outputs or {}) do assert(valid_prop_name(v.name), v.name.." is not valid output name") end
	for _, v in ipairs(commands or {}) do assert(valid_prop_name(v.name), v.name.." is not valid command name") end

	valid_device_meta(meta or default_meta())
	meta.app_inst = self._app_name
	meta.app = dc.get('APPS', self._app_name, 'name') or 'FreeIOE'
	meta.inst = meta.inst or meta.name -- 实际设备实例名称，如:BMS #2,PLC #2
	local dev = self._devices[sn]
	if dev then
		return dev
	end

	inputs = (inputs and #inputs > 0) and inputs or nil
	outputs = (outputs and #outputs > 0) and outputs or nil
	commands = (commands and #commands > 0) and commands or nil

	local props = {meta = meta, inputs = inputs, outputs = outputs, commands = commands}
	dev = dev_api:new(self, sn, props)
	self._devices[sn] = dev
	self._data_chn:publish('add_device', self._app_name, sn, props)
	return dev
end

---
-- 从应用中删除设备
-- @param dev: 要删除的设备对象
-- @return: true
---
function api:del_device(dev)
	dev:cleanup()
	return true
end

---
-- 获取设备对象以访问输入、输出和命令
-- 使用正确的密钥将能够写入输入值
-- @param sn: 设备序列号
-- @param secret: 写入访问的可选密钥
-- @return: 设备对象，未找到返回nil和错误信息
---
function api:get_device(sn, secret)
	assert(sn, "Device Serial Number is required!")
	local props = dc.get('DEVICES', sn)
	if not props then
		return nil, string.format("Device %s does not exist", sn)
	end
	return dev_api:new(self, sn, props, true, secret)
end

---
-- 向另一个应用发送控制命令
-- @param app: 目标应用名称
-- @param ctrl: 控制命令类型
-- @param params: 命令参数
-- @param priv: 用于结果关联的私有数据
---
function api:send_ctrl(app, ctrl, params, priv)
	self._ctrl_chn:publish('ctrl', self._app_name, app, ctrl, params, priv)
end

---
-- 将通信数据转储到通信通道
-- @param sn: 设备序列号
-- @param dir: 方向（send/recv）
-- @param ...: 要转储的通信数据
-- @return: 发布结果
---
function api:_dump_comm(sn, dir, ...)
	assert(sn)
	return self._comm_chn:publish(self._app_name, sn, dir, ioe.time(), ...)
end

---
-- 设置事件触发阈值限制（每分钟事件数）
-- @param count_per_min: 每分钟允许的最大事件数（1-127）
---
function api:_set_event_threshold(count_per_min)
	assert(count_per_min > 0 and count_per_min < 128)
	self._event_fire_buf = threshold_buffer:new(60, count_per_min, function(...)
		return self._event_chn:publish(...)
	end, function(...)
		self._logger:error('Event threshold reached:', ...)
	end)
end

---
-- 触发事件到事件通道
-- @param sn: 设备序列号
-- @param level: 事件严重性级别（debug、info、warning、error、fatal）
-- @param type_: 事件类型字符串
-- @param info: 事件描述字符串
-- @param data: 可选的事件数据表
-- @param timestamp: 可选的事件时间戳（默认为当前时间）
-- @return: 缓冲区推送结果
---
function api:_fire_event(sn, level, type_, info, data, timestamp)
	assert(sn and level and type_ and info)
	local type_ = app_event.type_to_string(type_)
	return self._event_fire_buf:push(self._app_name, sn, level, type_, info, data or {}, timestamp or ioe.time())
end

return api
