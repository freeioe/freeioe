local skynet = require 'skynet.manager'
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

local function ping_check(ip)
	assert(ip)
	local ping_ok = false
	for i = 1, 5 do
		if ping(ip) then
			ping_ok = true
			break
		end
		skynet.sleep(100)
	end
	if not ping_ok then
		log.error("Ping", ip, "Failed")
		return false, "Ping "..ip.." failed!"
	end
	return ping_ok
end

function tests.test_eth0()
	skynet.sleep(700)
	return ping_check('192.168.1.1')
end

function tests.test_eth1()
	skynet.sleep(600)
	local ping_ok = ping_check('192.168.2.1')
	if not ping_ok then
		return false, "Ping failed"
	end
	local usb_eth = require 'hwtest.gpio.usb_eth'
	return usb_eth('eth1', '0b95:772b')
end

function tests.test_modem()
	skynet.sleep(500)
	local ping_ok = ping_check('114.114.114.114')
	if not ping_ok then
		log.error("Modem network is not ready")
		return false, "Modem network is not ready"
	end

	local modem = require 'hwtest.gpio.modem'
	return modem('pcie', '2c7c:0125')
end

function tests.test_rtc()
	skynet.sleep(1000)
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
	skynet.sleep(500)
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
			if os.getenv('IOE_HWTEST_FINISH_HALT') then
				log.notice("Halt hardware two seconds later!!")
				skynet.timeout(200, function()
					log.notice("Halt hardware now!!")
					os.execute('halt')
				end)
			else
				log.notice("Abort FreeIOE two seconds later!!")
				skynet.timeout(200, function()
					log.notice("FreeIOE closing!!!")
					skynet.abort()
				end)
			end
		else
			leds_blink()
			log.notice("Hardware test failed!!!! Abort FreeIOE two seconds later!!")
			skynet.timeout(200, function()
				log.notice("FreeIOE closing!!!")
				skynet.abort()
			end)
		end
	end,
}
