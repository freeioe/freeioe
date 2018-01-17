local class = require 'middleclass'
local opcua = require 'opcua'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("IOT_OPCUA_SERVER_APP")
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
	self._nodes = {}
end

--- 设定变量的默认值
local default_vals = {
	int = 0,
	string = '',
}

--- 创建OPCUA变量
-- @param idx: 命名空间
-- @param devobj: 设备OPCUA对象
-- @param input: 输入项名称
-- @param device: 系统设备对象用以获取当前数值
local function create_var(idx, devobj, input, device)
	local var, err = devobj:getChild(input.name)
	if var then
		var:setDescription(opcua.LocalizedText.new('zh_CN', input.desc))
		return var
	end
	local attr = opcua.VariableAttributes.new()
	attr.displayName = opcua.LocalizedText.new("zh_CN", input.name)
	if input.desc then
		attr.description = opcua.LocalizedText.new("zh_CN", input.desc)
	end

	local current = device:get_input_prop(input.name, 'value')
	local val = input.vt and default_vals[input.vt] or 0.0
	attr.value = opcua.Variant.new(current or val)

	return devobj:addVariable(opcua.NodeId.new(idx, 0), input.name, attr)
end

--- 设定变量的当前值
-- @param var: OPCUA变量对象
-- @param value: 变量的当前值
-- @param timestamp: 时间戳
-- @param quality: 质量戳
local function set_var_value(var, value, timestamp, quality)
	-- TODO: for timestamp and quality
	var:setValue(opcua.Variant.new(value))

	--[[
	local val = opcua.DataValue.new(opcua.Variant.new(value))
	val.status = quality
	local tm = opcua.DateTime.fromUnixTime(math.floor(timestamp)) +  math.floor((timestamp%1) * 100) * 100000
	val.sourceTimestamp = tm
	--var.dataValue = val
	var:setDataValue(val)
	]]--
end

--- 创建数据回调对象
-- @param app: 应用实例对象
local function create_handler(app)
	local api = app._api
	local server = app._server
	local log = app._log
	local idx = app._idx
	local nodes = app._nodes
	return {
		--- 处理设备对象添加消息
		on_add_device = function(app, sn, props)
			--- 获取对象目录
			local objects = server:getObjectsNode()
			--- 使用设备SN来生成设备对象的ID
			local id = opcua.NodeId.new(idx, sn)
			local device = api:get_device(sn)

			---检测OPCUA对象是否已经存在
			local devobj, err = objects:getChild(idx..":"..sn)
			if not r or not devobj then
				--- 设备对象不存在增加设备对象
				local attr = opcua.ObjectAttributes.new()
				--- 设定显示名称
				attr.displayName = opcua.LocalizedText.new("zh_CN", "Device "..sn)
				--- 添加OPCUA对象
				devobj, err = objects:addObject(opcua.NodeId.new(idx, sn), sn, attr)
				if not devobj then
					log:warning('Create device object failed, error', devobj)
					return
				end
			end

			--- 记录设备对象
			local node = nodes[sn] or {
				device = device,
				devobj = devobj,
				vars = {}
			}
			local vars = node.vars
			--- 将设备的输入项映射成为OPCUA对象的变量
			for i, input in ipairs(props.inputs) do
				local var = vars[input.name]
				if not var then
					vars[input.name] = create_var(idx, devobj, input, device)
				else
					--- 如果存在尝试修改变量描述
					var:setDescription(opcua.LocalizedText.new('zh_CN', input.desc))
				end
			end
			nodes[sn] = node
		end,
		--- 处理设备对象删除消息
		on_del_device = function(app, sn)
			local node = nodes[sn]
			if node then
				--- 删除设备对象
				node:deleteNode(true)
			end
		end,
		--- 处理设备对象修改消息
		on_mod_device = function(app, sn, props)
			local node = nodes[sn]
			if not node or not node.vars then
				-- TODO:
			end
			local vars = node.vars
			for i, input in ipairs(props.inputs) do
				local var = vars[input.name]
				---不存在就增加变量，存在则修改描述，确保描述一致
				if not var then
					vars[input.name] = create_var(idx, node.devobj, input, node.device)
				else
					var:setDescription(opcua.LocalizedText.new('zh_CN', input.desc))
				end
			end
		end,
		--- 处理设备输入项数值变更消息
		on_input = function(app, sn, input, prop, value, timestamp, quality)
			local node = nodes[sn]
			if not node or not node.vars then
				log:error("Unknown sn", sn)
				return
			end
			--- 设定OPCUA变量的当前值
			local var = node.vars[input]
			if var and prop == 'value' then
				set_var_value(var, value, timestamp, quality)
			end
		end,
	}
end

--- 应用启动函数
function app:start()
	--- 处理OPCUA模块的日志
	local Level_Funcs = {}
	Level_Funcs[opcua.LogLevel.TRACE] = assert(self._log.trace)
	Level_Funcs[opcua.LogLevel.DEBUG] = assert(self._log.debug)
	Level_Funcs[opcua.LogLevel.INFO] = assert(self._log.info)
	Level_Funcs[opcua.LogLevel.WARNING] = assert(self._log.warning)
	Level_Funcs[opcua.LogLevel.ERROR] = assert(self._log.error)
	Level_Funcs[opcua.LogLevel.FATAL] = assert(self._log.fatal)
	Category_Names = {}
	Category_Names[opcua.LogCategory.NETWORK] = "network"
	Category_Names[opcua.LogCategory.SECURECHANNEL] = "channel"
	Category_Names[opcua.LogCategory.SESSION] = "session"
	Category_Names[opcua.LogCategory.SERVER] = "server"
	Category_Names[opcua.LogCategory.CLIENT] = "client"
	Category_Names[opcua.LogCategory.USERLAND] = "userland"
	Category_Names[opcua.LogCategory.SECURITYPOLICY] = "securitypolicy"

	self._logger = function(level, category, ...)
		Level_Funcs[level](self._log, Category_Names[category], ...)
	end
	opcua.setLogger(self._logger)

	--- 生成OPCUA服务器实例
	local server = opcua.Server.new()

	--- 设定服务器地址
	server.config:setServerURI("urn:://opcua.symid.com")

	--- 添加命名空间
	local id = self._sys:id()
	local idx = server:addNamespace("http://iot.symid.com/"..id)

	self._server = server
	self._idx = idx
	--- 设定回调处理对象
	self._handler = create_handler(self)
	self._api:set_handler(self._handler, true)

	self._sys:fork(function()
		local devs = self._api:list_devices() or {}
		for sn, props in pairs(devs) do
			self._handler.on_add_device(self, sn, props)
		end
	end)
	
	--- 启动服务器
	server:startup()

	self._log:notice("Started!!!!")
	return true
end

--- 应用退出函数
function app:close(reason)
	self._server:shutdown()
	self._server = nil
end

--- 应用运行入口
function app:run(tms)
	--- OPCUA模块运行入口
	while self._server.running do
		local ms = self._server:run_once(false)
		--- 暂停OPCUA模块运行，处理IOT系统消息
		self._sys:sleep(ms % 10)
	end
	print('XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX')

	return 1000
end

--- 返回应用对象
return app

