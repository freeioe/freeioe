local skynet = require "skynet"
local snax = require "skynet.snax"
local sprotoloader = require "sprotoloader"

local is_windows = package.config:sub(1,1) == '\\'

skynet.start(function()
	skynet.error("Skynet/IOT Start")
	skynet.uniqueservice("protoloader")
	if not is_windows and not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",7001)
	skynet.newservice("cfg")
	local serial = snax.newservice("serial", "/tmp/ttyS10")
	local serial2 = snax.newservice("serial", "/tmp/ttyS11")

	skynet.fork(function()
		local r, err = serial.req.open()
		if r then
			serial.req.write("AABBCC")
		else
			skynet.error("Open Serial Failed With Error", err)
		end
		local r, err = serial2.req.open()
		if r then
			serial2.req.write("AABBCC")
		else
			skynet.error("Open Serial Failed With Error", err)
		end

		skynet.exit()
	end)
end)
