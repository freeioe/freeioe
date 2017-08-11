local skynet = require "skynet"
local snax = require "skynet.snax"

local is_windows = package.config:sub(1,1) == '\\'

skynet.start(function()
	skynet.error("Skynet/IOT Start")
	if not is_windows and not os.getenv("IOT_RUN_AS_DAEMON") then
		local console = skynet.newservice("console")
	end
	os.execute("netstat -an | grep 7000")
	skynet.newservice("debug_console",7000)
	skynet.newservice("cfg")
	skynet.newservice("upgrader")

	local cloud = snax.uniqueservice("cloud")
	local appmgr = snax.uniqueservice("appmgr")
	--local app = appmgr.req.start("XXXX", {test="AAA"})
	local app = appmgr.req.start("iot")

	skynet.exit()
end)
