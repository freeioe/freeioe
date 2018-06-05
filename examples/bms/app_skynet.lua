local class = require 'middleclass'
local modbus = require 'modbus.init'
local sm_client = require 'modbus.skynet_client'
local socketchannel = require 'socketchannel'
local serialchannel = require 'serialchannel'

local app = class("SSKL_BMS_App")
app.API_VER = 1

local enable_fake_test = true

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = sys:data_api()
	self._log = sys:logger()
end

local TestU = {}
local inputs = {
	{ name = "Us01", desc = "单体电压01"},
	{ name = "Us02", desc = "单体电压02"},
	{ name = "Us03", desc = "单体电压03"},
	{ name = "Us04", desc = "单体电压04"},
	{ name = "Us05", desc = "单体电压05"},
	{ name = "Us06", desc = "单体电压06"},
	{ name = "Us07", desc = "单体电压07"},
	{ name = "Us08", desc = "单体电压08"},
	{ name = "Us09", desc = "单体电压09"},
	{ name = "Us10", desc = "单体电压10"},
	{ name = "Us11", desc = "单体电压11"},
	{ name = "Us12", desc = "单体电压12"},
	{ name = "Us13", desc = "单体电压13"},
	{ name = "Us14", desc = "单体电压14"},
	{ name = "Us15", desc = "单体电压15"},
	{ name = "Us16", desc = "单体电压16"},
	{ name = "Ts01", desc = "单体温度01"},
	{ name = "Ts02", desc = "单体温度02"},
	{ name = "Ts03", desc = "单体温度03"},
	{ name = "Ts04", desc = "单体温度04"},
	{ name = "Ts05", desc = "单体温度05"},
	{ name = "Ts06", desc = "单体温度06"},
	{ name = "Ts07", desc = "单体温度07"},
	{ name = "Ts08", desc = "单体温度08"},
	{ name = "Tenv", desc = "环境温度"},
	{ name = "Usmax", desc = "单体电压最大值"},
	{ name = "Usmin", desc = "单体电压最小值"},
	{ name = "Tshi", desc = "单体温度最高值"},
	{ name = "Tslo", desc = "单体温度最低值"},
	{ name = "UB", desc = "电池组电压"},
	{ name = "UBL", desc = "母线电压"},
	{ name = "Icc", desc = "充电电流"},
	{ name = "Ifd", desc = "放电电流"},
	{ name = "SOC", desc = "剩余容量%"},
	{ name = "CMax", desc = "额定容量Ah"},
	{ name = "CLeft", desc = "剩余容量"},
	{ name = "BNo", desc = "电池组号", vt="int"},
	{ name = "status", desc = "设备状态", vt="int"},
}

if enable_fake_test then
	inputs[#inputs + 1] = { name = "TestU", desc = "测试数据"}
end

function app:start()
	self._api:set_handler({
		on_ctrl = function(...)
			print(...)
		end,
	})

	local sys_id = self._sys:id()
	local config = self._conf or {
		--channel_type = "socket",
	}
	config.devs = config.devs or {
		{
			port = "/tmp/ttyS10",
			baudrate = 115200
		}
		--[[
		{
		host = "127.0.0.1",
		port = 1502,
		nodelay = true,
		},
		]]--
	}
	assert(config)

	local devs = {}
	local meta = self._api:default_meta()
	meta.name = "BMS"
	meta.description = "Shanshan BMS"
	meta.series = "X1"
	for i, v in ipairs(config.devs) do
		assert(v.port)
		self._log:info("Creating device via port", v.port)
		local dev_sn = sys_id.."."..self._sys:gen_sn("bg"..i)
		local dev = self._api:add_device(dev_sn, meta, inputs)
		local stat = dev:stat("device")
		local client = nil

		if config.channel_type == 'socket' then
			v.nodelay = v.nodelay or true
			client = sm_client(socketchannel, v, modbus.apdu_tcp, i)
		else
			client = sm_client(serialchannel, v, modbus.apdu_rtu, i)
		end

		client:set_io_cb(function(io, msg)
			dev:dump_comm(io, msg)
			if io == 'IN' then
				stat:inc('bytes_in', string.len(msg))
			else
				stat:inc('bytes_out', string.len(msg))
			end
		end)
		devs[#devs + 1] = {
			dev = dev,
			stat = stat,
			client = client
		}
	end
	self._devs = devs

	if enable_fake_test then
		self._sys:fork(function()
			while true do
				TestU = {
					math.random(),
					math.random()
				}
				self._sys:sleep(10000)
			end
		end)
	end

	return true
end

function app:close(reason)
	print(self._name, reason)
end

local regs = {
	{ "Us01", "int16", 2, 0.001 },
	{ "Us02", "int16", 2, 0.001 },
	{ "Us03", "int16", 2, 0.001 },
	{ "Us04", "int16", 2, 0.001 },
	{ "Us05", "int16", 2, 0.001 },
	{ "Us06", "int16", 2, 0.001 },
	{ "Us07", "int16", 2, 0.001 },
	{ "Us08", "int16", 2, 0.001 },
	{ "Us09", "int16", 2, 0.001 },
	{ "Us10", "int16", 2, 0.001 },
	{ "Us11", "int16", 2, 0.001 },
	{ "Us12", "int16", 2, 0.001 },
	{ "Us13", "int16", 2, 0.001 },
	{ "Us14", "int16", 2, 0.001 },
	{ "Us15", "int16", 2, 0.001 },
	{ "Us16", "int16", 2, 0.001 },
	{ "Ts01", "int16", 2 },
	{ "Ts02", "int16", 2 },
	{ "Ts03", "int16", 2 },
	{ "Ts04", "int16", 2 },
	{ "Ts05", "int16", 2 },
	{ "Ts06", "int16", 2 },
	{ "Ts07", "int16", 2 },
	{ "Ts08", "int16", 2 },
	{ "Tenv", "int16", 2 },
	{ "Usmax", "int16", 2, 0.001 },
	{ "Usmin", "int16", 2, 0.001 },
	{ "Tshi", "int16", 2 },
	{ "Tslo", "int16", 2 },
	{ "UB", "int16", 2, 0.01 },
	{ "UBL", "int16", 2, 0.01 },
	{ "Icc", "int16", 2, 0.01 },
	{ "Ifd", "int16", 2, 0.01 },
	{ "SOC", "int16", 2 },
	{ "CMax", "uint16", 2, 0.01 },
	{ "CLeft", "uint32", 4, 0.01 },
	{ "BNo", "uint16", 2 },
}

function app:invalid_bms(dev, stat, no, quality)
	local index = 1
	local now = self._sys:time()
	for _, reg in ipairs(regs) do
		if reg[4] then
			dev:set_input_prop(reg[1], "value", 0, now, quality)
		else
			if reg[1] == "BNo" then
				dev:set_input_prop(reg[1], "value", no, now, quality)
			else
				dev:set_input_prop(reg[1], "value", 0, now, quality)
			end
		end
	end
	dev:set_input_prop('status', 'value', 1, now, quality)

	if enable_fake_test then
		dev:set_input_prop("TestU", "value", TestU[no], now, 0)
	end
end

function app:read_bms(dev, client, stat, no)
	local base_address = 0x00
	local req = {
		func = 0x03,
		addr = base_address,
		len = 38,
	}
	local r, pdu, err = pcall(function(req, timeout) 
		stat:inc('packets_out', 1)
		return client:request(req, timeout)
	end, req, 1000)
	if not r then
		pdu = tostring(pdu)
		if string.find(pdu, 'timeout') then
			self._log:debug(pdu, err)
		else
			self._log:warning(pdu, err)
		end
		return self:invalid_bms(dev, stat, no, 1)
	end

	if not pdu then 
		self._log:warning("read failed: " .. err) 
		return self:invalid_bms(dev, stat, no, 1)
	end
	--self._log:trace("read input registers done!")
	stat:inc('packets_in', 1)

	local d = modbus.decode
	local len = d.uint8(pdu, 2)
	assert(len >= 38 * 2)

	local index = 1
	local now = self._sys:time()
	for _, reg in ipairs(regs) do
		local df = d[reg[2]]
		assert(df)
		local val = df(pdu, index + 2)
		index = index + reg[3]
		if reg[4] then
			val = val * reg[4]
			dev:set_input_prop(reg[1], "value", val, now, 0)
		else
			if reg[1] == "BNo" then
				dev:set_input_prop(reg[1], "value", no, now, 0)
			else
				dev:set_input_prop(reg[1], "value", math.tointeger(val), now, 0)
			end
		end
	end
	dev:set_input_prop('status', 'value', 0, now, 0)
	if enable_fake_test then
		dev:set_input_prop("TestU", "value", TestU[no], now, 0)
	end
end

function app:run(tms)
	for i, d in ipairs(self._devs) do
		self:read_bms(d.dev, d.client, d.stat, i)
	end
	return 1000
end

return app
