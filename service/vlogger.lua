local skynet = require "skynet.manager"
local log = require 'log'

local LOG = nil

local function create_log()
	LOG = log.new(
		"trace", -- maximum log level

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
		LOG.notice(string.format("[%08x]: %s", address, msg))
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

skynet.start(function()
	skynet.fork(create_log)
	skynet.register ".logger"
end)
