local class = require 'middleclass'
--- 导入需要的模块
local modbus = require 'modbus.init'
local sm_client = require 'modbus.skynet_client'
local socketchannel = require 'socketchannel'
local serialchannel = require 'serialchannel'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("XXXX_App")
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
	self._log:debug(name.." Application initlized")
end

--- 应用启动函数
function app:start()
	--- 设定回调处理函数(目前此应用只做数据采集)
	self._api:set_handler({
		on_ctrl = function(...)
			print(...)
		end,
	})

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()
	local config = self._conf or {
		channel_type = 'socket'
	}

	--- 添加10个采集项
	local inputs = {}
	for i = 1, 10 do
		inputs[#inputs + 1] = { 
			name='tag'..i,
			desc='tag'..i..' description',
		}
	end

	--- 生成设备的序列号
	local dev_sn = sys_id..".modbus_"..self._name
	--- 生成设备对象
	local dev = self._api:add_device(dev_sn, inputs)
	--- 生成设备通讯口统计对象
	local stat = dev:stat('port')
	local client = nil

	--- 获取配置
	if config.channel_type == 'socket' then
		opt = {
			host = "127.0.0.1",
			port = 1503,
			nodelay = true,
		}
		print('socket')
		client = sm_client(socketchannel, opt, modbus.apdu_tcp, 1)
	else
		opt = {
			port = "/dev/ttymxc1",
			baudrate = 115200
		}
		print('serial')
		client = sm_client(serialchannel, opt, modbus.apdu_rtu, 1)
	end
	--- 设定通讯口数据回调
	client:set_io_cb(function(io, msg)
		--- 输出通讯报文
		dev:dump_comm(io, msg)
		--- 计算统计信息
		if io == 'IN' then
			stat:inc('bytes_in', string.len(msg))
		else
			stat:inc('bytes_out', string.len(msg))
		end
	end)
	self._client1 = client
	self._dev1 = dev
	self._stat1 = stat

	return true
end

--- 应用退出函数
function app:close(reason)
	print(self._name, reason)
end

--- modbus寄存器数据解析
function decode_registers(raw, count)
	local d = modbus.decode
	local len = d.uint8(raw, 2)
	assert(len >= count * 2)
	local regs = {}
	--- 按照无符号短整数进行解析
	for i = 0, count - 1 do
		regs[#regs + 1] = d.uint16(raw, i * 2 + 3)
	end
	return regs
end

--- 应用运行入口
function app:run(tms)
	local client = self._client1
	if not client then
		return
	end

	--- 设定读取的起始地址和读取的长度
	local base_address = 0x00
	local req = {
		func = 0x03, -- 03指令
		addr = base_address, -- 起始地址
		len = 10, -- 长度
	}
	--- 读取数据
	local r, pdu, err = pcall(function(req, timeout) 
		--- 统计数据
		self._stat1:inc('packets_out', 1)
		--- 接口调用
		return client:request(req, timeout)
	end, req, 1000)

	if not r then 
		pdu = tostring(pdu)
		if string.find(pdu, 'timeout') then
			self._log:debug(pdu, err)
		else
			self._log:warning(pdu, err)
		end
		return
	end

	if not pdu then 
		self._log:warning("read failed: " .. err) 
		return
	end

	--- 统计数据
	self._log:trace("read input registers done!")
	self._stat1:inc('packets_in', 1)
	--- 解析数据
	local regs = decode_registers(pdu, 10)
	local now = self._sys:time()

	--- 将解析好的数据设定到输入项
	for r,v in ipairs(regs) do
		self._dev1:set_input_prop('tag'..r, "value", math.tointeger(v), now, 0)
	end

	--- 返回下一次调用run之前的时间间隔
	return tms
end

--- 返回应用对象
return app
