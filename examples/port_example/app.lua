local class = require 'middleclass'
local app_port = require 'app.port'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("PORT_EXAMPLE_APP")
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
	self._api = self._sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	--- 设备实例
	self._devs = nil

	self._log:debug("Port example application initlized")
end

--- 应用启动函数
function app:start()
	self._api:set_handler({
		--[[
		--- 处理设备输入项数值变更消息，当需要监控其他设备时才需要此接口，并在set_handler函数传入监控标识
		on_input = function(app, sn, input, prop, value, timestamp, quality)
		end,
		]]
		on_output = function(app, sn, output, prop, value)
		end,
		on_command = function(app, sn, command, param)
		end,	
		on_ctrl = function(app, command, param, ...)
		end,
	})

	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id..".example"

	--- 增加设备实例
	local inputs = {
		{name="tag1", desc="tag1 desc"}
	}

	local meta = self._api:default_meta()
	meta.name = "Example Device"
	meta.description = "Example Device Meta"

	self._dev = self._api:add_device(sn, meta, inputs)
	self._port = app_port:new({
		host = "127.0.0.1",
		port = 16000,
		nodelay = true
	})

	return true
end

--- 应用退出函数
function app:close(reason)
	if self._port then
		self._port:destroy(reason)
	end
end

--- 应用运行入口
function app:run(tms)
	local r, err = self._port:request('DDDDD', function(sock)
		local data, err = sock:read(4)
		if not data then
			return false, err
		end

		if string.len(data) > 1 then
			return true, data
		end
		return false, "eee"
	end, false, 1000)
	self._log:debug('Request returns:', r, err)

	return 10000 --下一采集周期为10秒
end

--- 返回应用对象
return app
