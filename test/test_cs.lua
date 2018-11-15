
local skynet = require "skynet"

skynet.start(function()
	skynet.error("Test Starting")

	skynet.error(skynet.call(".upgrader", "lua", "upgrade_core", "TEST", { version = 988 }))
	skynet.error(skynet.call(".upgrader", "lua", "install_app", "TEST2", { inst="test222", name="modbus", version = 988 }))
	skynet.error(skynet.call(".ioe_ext", "lua", "install_ext", "TEST3", { name="opcua", version = 988 }))
	skynet.error(skynet.call(".ioe_ext", "lua", "upgrade_ext", "TEST4", { name="frpc", version = 988 }))
	skynet.error("Test End!!!!")
end)
