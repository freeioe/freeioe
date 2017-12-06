local skynet = require "skynet"
local snax = require "skynet.snax"

local is_windows = package.config:sub(1,1) == '\\'

skynet.start(function()
	skynet.error("IOT@Skynet Starting")
	if not is_windows and not os.getenv("IOT_RUN_AS_DAEMON") then
		local console = skynet.newservice("console")
	end
	skynet.newservice("cfg")
	skynet.newservice("upgrader")

	local cloud = snax.uniqueservice("cloud")
	local appmgr = snax.uniqueservice("appmgr")
	-- This is one comm data buffer service for get one snapshot
	local commlog = snax.uniqueservice("commlog")

	pcall(skynet.newservice, "debug_console",7000)
	pcall(skynet.newservice, "lwf", 8808)

	skynet.exit()
end)
