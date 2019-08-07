local skynet = require 'skynet'
local log = require 'utils.log'
local rtc = require 'hwtest.other.rtc'
local leds = require 'hwtest.leds'
local ping = require 'hwtest.ethernet.ping'
local master_slave = require 'hwtest.stream.master_slave'
local serial = require 'hwtest.stream.serial'


local tests = {}

function tests.test_serial()
	local ports = serial:new()
	local s1 = {
		port = '/dev/ttyS1',
		baudrate = 115200
	}
	local s2 = {
		port = '/dev/ttyS2',
		baudrate = 115200
	}
	ports:open(s1, s2)

	local r, reports = ports:run(master_slave:new(16, 256))
	if not r then
		log.debug("serial failed")
		return false
	end
	log.debug('Serial passed', reports.master.passed, reports.slave.passed)

	return reports.master.passed >= 10 and reports.slave.passed >= 10
end

function tests.test_eth0()
	log.debug("Ping", '192.168.1.1')
	return ping('192.168.1.1')
end

function tests.test_eth1()
	log.debug("Ping", '192.168.2.1')
	return ping('192.168.2.1')
	--return true
end

function tests.test_modem()
	local ping_ok = false
	for i = 1, 5 do
		if ping('8.8.8.8') then
			ping_ok = true
			break
		end
		skynet.sleep(100)
	end
	if not ping_ok then
		log.debug("Modem network is not ready")
		return false, "Modem network is not ready"
	end

	local modem = require 'hwtest.gpio.modem'
	return modem('pcie', '2c7c:0125')
end

function tests.test_rtc()
	return rtc()
end

function tests.test_emmc()
	return true
end

function tests.test_eeprom()
	return true
end

function tests.test_button()
	return true
end

function tests.test_led()
	skynet.fork(function()
		leds('kooiot:green:cloud')
	end)
	skynet.fork(function()
		leds('kooiot:green:bs')
	end)
	skynet.fork(function()
		leds('kooiot:green:gs')
	end)
	skynet.fork(function()
		leds('kooiot:green:modem')
	end)
	skynet.fork(function()
		leds('kooiot:green:status')
	end)

	skynet.sleep(3000)
	return true
end


local function _leds_on(led_name)
	local on_cmd = 'echo 255 > /sys/class/leds/'..led_name..'/brightness'
	os.execute(on_cmd)
end

local function leds_on()
	_leds_on('kooiot:green:cloud')
	_leds_on('kooiot:green:bs')
	_leds_on('kooiot:green:gs')
	_leds_on('kooiot:green:modem')
	_leds_on('kooiot:green:status')

	if os.getenv('IOE_HWTEST_FINISH_HALT') then
		skynet.timeout(200, function()
			os.execute('halt')
		end)
	end
end

local function _leds_blink(led_name)
	local cmd = 'echo heartbeat > /sys/class/leds/'..led_name..'/trigger'
	os.execute(cmd)
end

local function leds_blink()
	_leds_blink('kooiot:green:cloud')
	_leds_blink('kooiot:green:bs')
	_leds_blink('kooiot:green:gs')
	_leds_blink('kooiot:green:modem')
	_leds_blink('kooiot:green:status')
end

return  {
	tests = tests,
	finish = function(success)
		if success then
			leds_on()
		else
			leds_blink()
		end
	end,
}
