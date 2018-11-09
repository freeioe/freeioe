local skynet = require "skynet.manager"
local dc = require 'skynet.datacenter'
local coroutine = require 'skynet.coroutine'
local log = require 'utils.log'


local function exec_all(cmd)
	local cmd = cmd..' 2>/dev/null'
	local f, err = io.popen(cmd)
	if not f then
		return nil, err
	end
	local s = f:read('*a')
	f:close()
	return s
end

local command = {}
local command_running = {}

function command.EXEC(cmd)
	log.debug("::EXEC_SAL:: Execute command:", cmd)

	command_running[coroutine.running()] = skynet.now()

	return exec_all(cmd)
end

function command.CLEAN()
	for k, v in pairs(command_running) do
		print(k, v)
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	skynet.register ".EXEC_SAL"

	skynet.fork(function()
		while true do
			command.CLEAN()
			skynet.sleep(500)
		end
	end)
end)
