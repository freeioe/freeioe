local snax = require 'skynet.snax'
local ioe = require 'ioe'

local LOG
local listeners = {}

function accept.log(lvl, ...)
	local f = LOG[lvl]
	if not f then
		f = LOG.notice
	end
	f(...)
	for handle, srv in pairs(listeners) do
		srv.post.log(ioe.time(), lvl, ...)
	end
end

function accept.listen(handle, type)
	listeners[handle] = snax.bind(handle, type)
	return true
end

function accept.unlisten(handle)
	listeners[handle] = nil
	return true
end

function init(...)
	local log = require 'log'

	local lname = 'freeioe'
	local max_lvl = os.getenv('IOE_LOG_LEVEL') or 'info'

	LOG = log.new(
		max_lvl, -- maximum log level

		-- Writer
		require 'log.writer.list'.new(               -- multi writers:
			require "log.writer.console.color".new(),  -- * console color
			require 'log.writer.file.roll'.new('./logs', lname..".log", 4, 4*1024*1024)
		),

		-- Formatter
		require "log.formatter.concat".new('\t')
	)
end

function exit(...)
end
