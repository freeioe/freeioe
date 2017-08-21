local skynet = require 'skynet'
local snax = require 'skynet.snax'

local LOG
local reg_map = {}

function accept.log(lvl, ...)
	local f = LOG[lvl]
	if not f then
		f = LOG.notice
	end
	f(...)
	for handle, srv in pairs(reg_map) do
		srv.post.log(skynet.time(), lvl, ...)
	end
end

function accept.reg_snax(handle, type)
	reg_map[handle] = snax.bind(handle, type)
	return true
end

function accept.unreg_snax(handle)
	reg_map[handle] = nil
	return true
end

function init(...)
	local log = require 'log'

	local lname = 'skynet'
	local max_lvl = os.getenv('IOT_LOG_LEVEL') or 'info'

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
