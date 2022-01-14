local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local log = require 'log'

local LOG = nil
local function create_log()
	local max_lvl = os.getenv('IOE_LOG_LEVEL') or 'info'
	if os.getenv('IOE_DEVELOPER_MODE') then
		max_lvl = 'trace'
	end
	LOG = log.new(
		max_lvl, -- maximum log level

		-- Writer
		require 'log.writer.list'.new(               -- multi writers:
			require "log.writer.console.color".new(),  -- * console color
			--require 'log.writer.file.roll'.new('./logs', "freeioe_sys.log", 4, 1*1024*1024)
			require 'log.writer.file.roll'.new('./logs', "freeioe.log", 4, 4*1024*1024)
			--[[
			require 'log.writer.format'.new(
				require 'log.logformat.syslog'.new(),
				require 'log.writer.net.udp'.new('127.0.0.1', 514)
			)
			]]--
		),

		-- Formatter
		require "log.formatter.concat".new('\t'),
		require 'log.logformat.default'.new()
	)
end

local listeners = {}

local function _listen(handle, type)
       listeners[handle] = snax.bind(handle, type)
       return true
end

local function _unlisten(handle)
       listeners[handle] = nil
       return true
end

local _fmt = require 'log.formatter.concat'.new('\t')

local function post_to_listeners(lvl, ...)
	local msg = _fmt(...)
	local now = skynet.time()
	for handle, srv in pairs(listeners) do
		srv.post.log(now, lvl, msg)
	end
end

local function _log_content(address, level, fmt, ...)
	local hdr = string.format("[%08x]: %s", address, fmt)
	local f = assert(LOG[level] or LOG.notice)

	f(hdr, ...)
	post_to_listeners(level, hdr, ...)
end

skynet.register_protocol {
	name = "text",
	id = skynet.PTYPE_TEXT,
	unpack = skynet.tostring,
	dispatch = function(_, address, msg)
		_log_content(address, 'notice', '::SYS:: '..msg)
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

--- Create log files
create_log()

skynet.start(function()
	skynet.dispatch("lua", function(session, address, level, ...)
		if level == '__LISTEN__' then
			skynet.ret(skynet.pack(_listen(...)))
		elseif level == '__UNLISTEN__' then
			skynet.ret(skynet.pack(_unlisten(...)))
		else
			skynet.ret(skynet.pack(_log_content(address, level, ...)))
		end
	end)

	--- Latest skynet will register .logger for us, keep this register for make this working with older skynet
	skynet.register ".logger"
	dc.set('FREEIOE.LOGGER', ".logger")
end)
