local skynet = require "skynet"

local LOG

function accept.log(lvl, ...)
	local f = LOG[lvl]
	if not f then
		f = LOG.notice
	end
	f(...)
end

function init(...)
	local log = require 'log'

	local lname = 'skynet'

	LOG = log.new(
		"trace", -- maximum log level

		-- Writer
		require 'log.writer.list'.new(               -- multi writers:
			require "log.writer.console.color".new(),  -- * console color
			require 'log.writer.file.roll'.new('./logs', lname..".log", 64, 32*1024*1024)
		),

		-- Formatter
		require "log.formatter.concat".new('\t')
	)
end

function exit(...)
end
