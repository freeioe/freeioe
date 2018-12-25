local skynet = require "skynet.manager"
local snax = require 'skynet.snax'
local log = require 'log'
local ioe = require 'ioe'

local LOG = nil
local listeners = {}

local function create_log()
	local max_lvl = os.getenv('IOE_LOG_LEVEL') or 'info'
	LOG = log.new(
		max_lvl, -- maximum log level

		-- Writer
		require 'log.writer.list'.new(               -- multi writers:
			require "log.writer.console.color".new(),  -- * console color
			require 'log.writer.file.roll'.new('./logs', "freeioe_sys.log", 4, 1*1024*1024)
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
		for handle, srv in pairs(listeners) do
			srv.post.log(ioe.time(), 'notice', content)
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

function command.listen(handle, type)
	listeners[handle] = snax.bind(handle, type)
	return true
end

function command.unlisten(handle)
	listeners[handle] = nil
	return true
end

create_log()

skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.lower(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)

	--- Latest skynet will register .logger for us, keep this register for make this working with older skynet
	skynet.register ".logger"
end)
