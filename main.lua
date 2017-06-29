local skynet = require "skynet"
local snax = require "skynet.snax"

local is_windows = package.config:sub(1,1) == '\\'

local function set_defaults()
	local dc = require 'skynet.datacenter'

	dc.set("CLOUD", "ID", "IDIDIDIDID")
	dc.set("CLOUD", "HOST", "localhost")
	dc.set("CLOUD", "PORT", 1883)
	dc.set("CLOUD", "TIMEOUT", 300)

	dc.set("CLOUD", "PKG_HOST_URL", "http://localhost:8000")
end

skynet.start(function()
	skynet.error("Skynet/IOT Start")
	if not is_windows and not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",7000)
	set_defaults()
	skynet.newservice("cfg")

	local appmgr = snax.uniqueservice("appmgr")
--	local app = appmgr.req.start("XXXX", {test="AAA"})
	local app = appmgr.req.start("modbus", {test="AAA"})

	local sn = os.getenv("IOT_SN") or "IDIDIDIDID"
	local cloud = snax.uniqueservice("cloud", sn, "localhost")
	local r, err = cloud.req.connect()
	--cloud.post.enable_log(true)

	skynet.exit()
end)
