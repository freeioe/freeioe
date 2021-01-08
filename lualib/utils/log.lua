local inskynet, skynet = pcall(require, 'skynet')

if not inskynet then
	local log = require 'log'

	local lname = 'log'

	local LOG = log.new(
		"trace", -- maximum log level

		-- Writer
		require 'log.writer.list'.new(               -- multi writers:
			require "log.writer.console.color".new(),  -- * console color
			require 'log.writer.file.roll'.new('./logs', lname..".log", 64, 32*1024*1024)
		),

		-- Formatter
		require "log.formatter.concat".new('\t')
	)

	return LOG
else
	local make_func = function(name)
		local name = name
		return function(...)
			skynet.send('.logger', 'lua', name, ...)
		end
	end
	local LOG = {}
	LOG.emerg = make_func('emerg')
	LOG.alert = make_func('alert')
	LOG.fatal = make_func('fatal')
	LOG.error = make_func('error')
	LOG.warning = make_func('warning')
	LOG.notice = make_func('notice')
	LOG.info = make_func('info')
	LOG.debug = make_func('debug')
	LOG.trace = make_func('trace')
	return LOG
end

