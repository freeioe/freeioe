local class = require 'middleclass'
--- 导入需要的模块
local modbus = require 'modbus.init'
local sm_client = require 'modbus.skynet_client'
local socketchannel = require 'socketchannel'
local serialchannel = require 'serialchannel'
local csv_tpl = require 'csv_tpl'

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

	csv_tpl.init(self._sys:app_dir())

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()
	local config = self._conf or {}

	config.channel_type = config.channel_type or 'socket'
	if config.channel_type == 'socket' then
		config.opt = config.opt or {
			host = "127.0.0.1",
			port = 1503,
			nodelay = true,
		}
	else
		config.opt = config.opt or {
			port = "/dev/ttymxc1",
			baudrate = 115200
		}
	end

	config.devs = config.devs or {
		{ unit = 1, name = 'bms01', sn = 'xxx-xx-1', tpl = 'bms' },
		{ unit = 2, name = 'bms02', sn = 'xxx-xx-2', tpl = 'bms2' },
	}

	self._devs = {}
	for _, v in ipairs(config.devs) do
		assert(v.sn and v.name and v.unit and v.tpl)

		--- 生成设备的序列号
		local dev_sn = sys_id.."."..v.sn
		local tpl, err = csv_tpl.load_tpl(v.tpl)
		if not tpl then
			self._log:error("loading csv tpl failed", err)
		else
			local meta = self._api:default_meta()
			meta.name = tpl.meta.name or "Modbus"
			meta.description = tpl.meta.desc or "Modbus Device"
			meta.series = tpl.meta.series or "XXX"
			meta.inst = v.name
			--- inputs
			local inputs = {}
			for _, v in ipairs(tpl.inputs) do
				inputs[#inputs + 1] = {
					name = v.name,
					desc = v.desc,
					vt = v.vt
				}
			end
			inputs[#inputs + 1] = { name = "status", desc = "设备状态", vt="int"}
			--- 生成设备对象
			local dev = self._api:add_device(dev_sn, meta, inputs)
			--- 生成设备通讯口统计对象
			local stat = dev:stat('port')

			table.insert(self._devs, {
				unit = v.unit,
				dev = dev,
				tpl = tpl,
				stat = stat,
			})
		end
	end

	local client = nil

	--- 获取配置
	if config.channel_type == 'socket' then
		client = sm_client(socketchannel, config.opt, modbus.apdu_tcp, 1)
	else
		client = sm_client(serialchannel, config.opt, modbus.apdu_rtu, 1)
	end
	self._client = client

	return true
end

--- 应用退出函数
function app:close(reason)
	print(self._name, reason)
end

function app:read_packet(dev, stat, unit, pack)
	--- 设定读取的起始地址和读取的长度
	local base_address = pack.saddr or 0x00
	local req = {
		func = tonumber(pack.func) or 0x03, -- 03指令
		addr = base_address, -- 起始地址
		len = pack.len or 10, -- 长度
		unit = unit or pack.unit
	}

	--- 设定通讯口数据回调
	self._client:set_io_cb(function(io, msg)
		--- 输出通讯报文
		dev:dump_comm(io, msg)
		--- 计算统计信息
		if io == 'IN' then
			stat:inc('bytes_in', string.len(msg))
		else
			stat:inc('bytes_out', string.len(msg))
		end
	end)
	--- 读取数据
	local r, pdu, err = pcall(function(req, timeout) 
		--- 统计数据
		stat:inc('packets_out', 1)
		--- 接口调用
		return self._client:request(req, timeout)
	end, req, 1000)

	if not r then 
		pdu = tostring(pdu)
		if string.find(pdu, 'timeout') then
			self._log:debug(pdu, err)
		else
			self._log:warning(pdu, err)
		end
		return self:invalid_dev(dev, pack)
	end

	if not pdu then 
		self._log:warning("read failed: " .. err) 
		return self:invalid_dev(dev, pack)
	end

	--- 统计数据
	self._log:trace("read input registers done!", unit)
	stat:inc('packets_in', 1)

	--- 解析数据
	local d = modbus.decode
	local len = d.uint8(pdu, 2)
	--assert(len >= 38 * 2)

	for _, input in ipairs(pack.inputs) do
		local df = d[input.dt]
		assert(df)
		local index = input.saddr
		local val = df(pdu, index + 2)
		if input.rate and input.rate ~= 1 then
			val = val * input.rate
			dev:set_input_prop(input.name, "value", val)
		else
			dev:set_input_prop(input.name, "value", math.tointeger(val))
		end
	end
	dev:set_input_prop('status', 'value', 0)
end

function app:invalid_dev(dev, pack)
	for _, input in ipairs(pack.inputs) do
		dev:set_input_prop(input.name, "value", 0, nil, 1)
	end
	dev:set_input_prop('status', 'value', 1, nil, 1)
end

function app:read_dev(dev, stat, unit, tpl)
	for _, pack in ipairs(tpl.packets) do
		self:read_packet(dev, stat, unit, pack)
	end
end

--- 应用运行入口
function app:run(tms)
	if not self._client then
		return
	end

	for _, dev in ipairs(self._devs) do
		self:read_dev(dev.dev, dev.stat, dev.unit, dev.tpl)
	end

	--- 返回下一次调用run之前的时间间隔
	return tms
end

--- 返回应用对象
return app
