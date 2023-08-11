local skynet = require "skynet.manager"
local snax = require "skynet.snax"
local lfs = require 'lfs'

local is_windows = package.config:sub(1,1) == '\\'

local function start_ioe_services()
	skynet.newservice("cfg")
	skynet.newservice("upgrader")
	skynet.newservice("ioe_ext")

	pcall(skynet.newservice, "debug_console", 6606)
	pcall(skynet.newservice, "lwf", 8808)

	-- local logger = snax.uniqueservice("logger")
	local cloud = snax.uniqueservice("cloud")
	local appmgr = snax.uniqueservice("appmgr")
	-- This is one comm data buffer service for get one snapshot
	local commlog = snax.uniqueservice("buffer")
	local ws = snax.uniqueservice("ws")

	-- Enable ubus when lsocket exits and OS is openwrt
	local lsocket_loaded, lsocket = pcall(require, 'lsocket')
	if lsocket_loaded and lfs.attributes('/etc/openwrt_release', 'mode') then
		skynet.error("Starts ubus service!!!")
		local ubus = snax.uniqueservice('ubus')
	else
		skynet.error("Unix socket for ubus not found, ubus service will not be started!!!")
		--local ubus = snax.uniqueservice('ubus', '172.30.11.230', 11000)
		--local ubus = snax.uniqueservice('ubus', '/tmp/ubus.sock')
	end
end

skynet.start(function()
	skynet.error("FreeIOE starting...")
	if not lfs.currentdir() then
		skynet.error("FreeIOE current directory is nil!")
		skynet.sleep(5)
		skynet.abort()
		return
	end

	if _VERSION ~= 'Lua 5.4' then
		skynet.error("FreeIOE required run with skynet built with Lua 5.4!!!!")
	end

	--skynet.newservice("exec_sal")
	if not is_windows and not os.getenv("IOE_RUN_AS_DAEMON") then
		local console = skynet.newservice("console")
	end

	local r, err = pcall(start_ioe_services)
	if not r then
		skynet.error("FreeIOE start services failed!")
		skynet.sleep(5)
		skynet.abort()
	end

	skynet.exit()
end)
