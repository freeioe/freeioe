--- 导入需求的模块
local class = require 'middleclass'
local opcua = require 'opcua'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("FREEIOE_SYMLINK_OPCUA_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	--- 获取数据接口
	self._api = sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	self._connect_retry = 1000
end

---
-- 检测连接可用性
function app:is_connected()
	if self._client then
		return 0 ~= self._client:getState()
	else
		return false
	end
end

---
-- 获取设备的OpcUa节点
function app:get_device_node(namespace, obj_name)
	if not self:is_connected() then
		self._log:warning("Client is not connected!")
		return
	end

	local client = self._client
	local nodes = self._nodes

	--- 获取Objects节点
	local objects = client:getObjectsNode()
	--- 获取名字空间的id号
	local idx, err = client:getNamespaceIndex(namespace)
	if not idx then
		self._log:warning("Cannot find namespace", err)
		return
	end
	--- 获取设备节点
	local devobj, err = objects:getChild(idx..":"..obj_name)
	if not devobj then
		self._log:error('Device object not found', err)
		return
	else
		self._log:debug("Device object found", devobj)
	end

	--- 返回节点对象
	return {
		idx = idx,
		name = obj_name,
		device = device,
		devobj = devobj,
		vars = {}
	}
end

---
-- 定义需要获取数据的输入项
local inputs = {
	{ name = "state", desc = "SymLink client connection state"},
}

local function create_input(inputs, nodes, opcua_var)
	-- Variable
	local input = {
		name = opcua_var.id.index,
		desc = opcua_var:getDescription().text
	}
	if string.sub(input.name, 1, 1) == '#' then
		input.name = string.sub(input.name, 2)
	end
	--print("Variable", input.name, input.desc, opcua_var)

	inputs[#inputs + 1] = input
	nodes[#nodes + 1] = {
		obj = opcua_var,
		name = input.name
	}
end

local function map_node(inputs, nodes, opcua_node)
	local children = opcua_node:getChildren()
	for _, v in ipairs(children) do
		--print("Child", v:getBrowseName(), v)

		if v.nodeClass == 2 then
			create_input(inputs, nodes, v)
		end
		if v.nodeClass == 1 then
			--print("Object", v:getBrowseName(), v)
			map_node(inputs, nodes, v)
		end
	end
end

---
-- 连接成功后的处理函数
function app:on_connected(client)
	-- Cleanup nodes buffer
	self._inputs = inputs
	self._nodes = {}
	-- Set client object
	self._client = client

	--- Get opcua object instance by namespace and browse name
	-- 根据名字空间和节点名称获取OpcUa对象实体
	local namespace = self._conf.namespace or "urn:unconfigured:application"
	local obj_name = self._conf.root_object or "SymLink"
	local node, err = self:get_device_node(namespace, obj_name)
	---
	-- 获取设备对象节点下的变量节点
	if node then
		--print("Load SymLink Node")
		map_node(self._inputs, self._nodes, node.devobj)
		self._dev:mod(self._inputs)
	end
end

---
-- 连接断开后的处理函数
function app:on_disconnect()
	self._nodes = {}
	self._inputs = {}
	self._client = nil
	self._sys:timeout(self._connect_retry, function() self:connect_proc() end)
	self._connect_retry = self._connect_retry * 2
	if self._connect_retry > 2000 * 64 then
		self._connect_retry = 2000
	end
end

---
-- 连接处理函数
function app:connect_proc()
	self._log:notice("OPC Client start connection!")
	local client = self._client_obj

	--local username = self._conf.username or "user1"
	--local password = self._conf.password or "password"
	--local r, err = client:connect_username(username, password)
	local ret = client:connect()
	if ret == 0 then
		self._log:notice("OPC Client connect successfully!", self._sys:time())
		self._connect_retry = 2000
		self:on_connected(client)
	else
		local err = opcua.getStatusCodeName(ret)
		self._log:error("OPC Client connect failure!", err, self._sys:time())
		self:on_disconnect()
	end
end

--- 应用启动函数
function app:start()
	self._nodes = {}
	self._devs = {}

	--- 设定OpcUa连接配置
	local config = opcua.ConnectionConfig.new()
	config.protocolVersion = 0  -- 协议版本
	config.sendBufferSize = 65535  -- 发送缓存大小
	config.recvBufferSize = 65535  -- 接受缓存大小
	config.maxMessageSize = 0	-- 消息大小限制
	config.maxChunkCount = 0	--

	--- 生成OpcUa客户端对象
	local ep = self._conf.endpoint or "opc.tcp://127.0.0.1:4840"
	local client = opcua.Client.new(ep, 5000, 10 * 60 * 1000, config)
	self._client_obj = client

	--- 设定接口处理函数
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
			-- TODO: write value to symlink
			self._log:warning("Write value to symlink", output, prop, value)
			for _, node in pairs(self._nodes) do
				if node.name == output then
					local val = nil
					if type(value) == 'number' then
						if prop == 'int_value' then
							val = opcua.Variant.int32(value)
						else
							val = opcua.Variant.new(value * 1.0)
						end
					else
						-- boolean, string
						val = opcua.Variant.new(value)
					end

					local r = node.obj:setValue(val)
					if r ~= 0 then
						self._log:error("Failed to write value", opcua.getStatusCodeName(r))
						return nil, opcua.getStatusCodeName(r)
					end
				end
			end
		end,
		on_ctrl = function(app, command, param, ...)
			print(...)
		end
	})

	--- 创建设备对象实例
	local sys_id = self._sys:id()
	local meta = self._api:default_meta()
	meta.name = "SymLink"
	meta.description = "SymLink Device"
	meta.series = "Q102"
	self._dev = self._api:add_device(sys_id..'.symlink', meta, inputs)

	--- 发起OpcUa连接
	self._sys:fork(function() self:connect_proc() end)

	return true
end

--- 应用退出函数
function app:close(reason)
	print('close', self._name, reason)
	--- 清理OpcUa客户端连接
	self._client = nil
	if self._client_obj then
		self._nodes = {}
		self._client_obj:disconnect()
		self._client_obj = nil
	end
end

--- 应用运行入口
function app:run(tms)
	if not self._client then
		return 1000
	end
	local dev = self._dev

	local state = self._client:getState()
	dev:set_input_prop("client_state", "value", state)

	if 0 == state then
		self._sys:fork(function() self:connect_proc() end)
		self._client = nil
		return 1000
	end

	--print('-----------')
	--- 获取节点当前值数据
	for _, node in pairs(self._nodes) do
		--print(node.name, node.obj)
		local dv = node.obj:getValue()
		--[[
		print(dv, dv:isEmpty(), dv:isScalar())
		print(dv:asLong(), dv:asDouble(), dv:asString())
		]]--
		local now = self._sys:time()
		--- 设定当前值
		--print(node.name, dv:asDouble(), now)
		dev:set_input_prop(node.name, "value", dv:asDouble(), now, 0)

		--[[
		--- Test write value
		local value = 10
		local val = opcua.Variant.new(value * 1.0)
		local r = node.obj:setValue(val)
		if r ~= 0 then
			self._log:debug("Failed to write value", opcua.getStatusCodeName(r))
		else
			self._log:debug("Write Value OK!!!!!!!")
		end
		]]--
	end

	--- 返回下一次调用run函数的间隔
	return self._conf.run_sleep or 1000
end

--- 返回应用对象
return app

