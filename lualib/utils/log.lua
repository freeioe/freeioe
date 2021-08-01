--- DO NOT USE THIS in application
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
	local dc = require 'skynet.datacenter'
	local make_func = function(name)
		local name = name
		local ln = nil
		return function(...)
			local t = {}
			for k, v in ipairs({...}) do
				local s = tostring(v)
				if string.len(s) <= 512 then
					t[#t + 1] = s
				else
					t[#t + 1] = string.sub(s, 1, 510) .. '.....'
				end
			end
			--assert(t[1] ~= 'not enough memory')
			skynet.send('.logger', 'lua', name, table.unpack(t))

			--[[ There skynet.lua may asserts on proto[name] name is 'lua'
			--ln = ln or dc.wait('FREEIOE.LOGGER')
			if not ln then
				print('create')
				skynet.fork(function(...)
					ln = dc.wait('FREEIOE.LOGGER')
					skynet.send(ln, 'lua', name, ...)
				end, ...)
			else
				skynet.send(ln, 'lua', name, ...)
			end
			]]--
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

