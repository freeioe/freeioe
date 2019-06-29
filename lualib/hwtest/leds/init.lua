local skynet = require 'skynet'

return function(led_name, seconds)
	local seconds = seconds or 10

	local on_cmd = 'echo 255 > /sys/class/leds/'..led_name..'/brightness'
	local off_cmd = 'echo 0 > /sys/class/leds/'..led_name..'/brightness'

	local count = seconds * 2
	for i = 1, count do
		os.execute(on_cmd)
		skynet.sleep(25)
		os.execute(off_cmd)
		skynet.sleep(25)
	end
end
