local skynet = require 'skynet'
local snax = require 'skynet.snax'

local params = {...}

if #params < 2 then
	skynet.error("USAGE: app <start/stop/restart> <instance name>")
	return
end

skynet.start(function()
	local appmgr = snax.queryservice('appmgr')

	local method = 'app_'..params[1]

	appmgr.post[method](table.unpack(params, 2))

	skynet.error("DONE")
	skynet.exit()
end)
