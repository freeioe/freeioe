local skynet = require "skynet.manager"
local snax = require 'skynet.snax'
local log = require 'log'

local LOG = nil
local reg_map = {}

local function create_log()
	local max_lvl = os.getenv('IOE_LOG_LEVEL') or 'info'
	LOG = log.new(
		max_lvl, -- maximum log level

		-- Writer
		require 'log.writer.list'.new(               -- multi writers:
			require "log.writer.console.color".new(),  -- * console color
			require 'log.writer.file.roll'.new('./logs', "skynet_sys.log", 4, 1*1024*1024)
		),

		-- Formatter
		require "log.formatter.concat".new('\t')
	)
end

skynet.register_protocol {
	name = "text",
	id = skynet.PTYPE_TEXT,
	unpack = skynet.tostring,
	dispatch = function(_, address, msg)
		local content = string.format("[%08x]: %s", address, msg)
		LOG.notice(content)
		for handle, srv in pairs(reg_map) do
			srv.post.log(skynet.time(), 'notice', content)
		end
	end
}

skynet.register_protocol {
	name = "SYSTEM",
	id = skynet.PTYPE_SYSTEM,
	unpack = function(...) return ... end,
	dispatch = function(...)
		LOG.error("SYSTEM:", ...)
	end
}

local command = {}

function command.reg_snax(handle, type)
	reg_map[handle] = snax.bind(handle, type)
	return true
end

function command.unreg_snax(handle)
	reg_map[handle] = nil
	return true
end

skynet.start(function()
	skynet.fork(create_log)

	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.lower(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)

	skynet.register ".logger"
end)
