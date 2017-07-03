local skynet = require "skynet"
local snax = require "skynet.snax"

local is_windows = package.config:sub(1,1) == '\\'

skynet.start(function()
	skynet.error("Skynet/IOT Start")
	if not is_windows and not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",7000)
	skynet.newservice("cfg")
	skynet.newservice("upgrader")

	local appmgr = snax.uniqueservice("appmgr")
	--local app = appmgr.req.start("XXXX", {test="AAA"})
	local app = appmgr.req.start("modbus", {test="AAA"})

	local cloud = snax.uniqueservice("cloud")
	local r, err = cloud.req.connect()

	skynet.exit()
end)
