local class = require 'middleclass'
local log = require 'utils.log'
local formatter = require 'log.formatter.concat'.new()

local logger = class("APP_MGR_LOG")

function logger:initialize(log, name)
	self._log = log
	self._log_buf = {}
	self._name = name
end

function logger:log(level, info, ...)
	--lvl = log.lvl2number(level)

	local info = self._name and '::'..self._name..':: '..info or info
	local s = formatter(info, ...)
	local now = os.time()
	local los = self._log_buf[level]
	if los then
		if los.s == s and (now - los.t) < 60 then
			los.t = now
			los.c = los.c + 1
			if (now - los.ts) >= (60 * 10) then
				local f = assert(self._log[level])
				f(string.format('[%d ZIPED %d-%d]', los.c, los.ts, now), s)
				los.c = 0
				los.ts = now
			end
			return
		else
			if los.c > 0 then
				local f = assert(self._log[level])
				f(string.format('[%d ZIPED %d-%d ]', los.c, los.ts, los.t), s)
			end
		end
	end

	self._log_buf[level] = {
		ts = now,
		t = now,
		s = s,
		c = 0,
	}
	local f = assert(self._log[level])
	return f(...)
end

function logger:debug_log(level, info, ...)
	local info = self._name and '::'..self._name..':: '..info or info
	--lvl = log.lvl2number(level)
	local f = assert(self._log[level])
	return f(info, ...)
end

local function make_func(logger, name)
	logger[name] = function(self, ...)
		--[[
		if os.getenv('IOE_LOG_LEVEL') == 'trace' then
			return self:debug_log(name, ...)
		end
		return self:log(name, ...)
		]]--
		return self:debug_log(name, ...)
	end
end

make_func(logger, 'trace')
make_func(logger, 'debug')
make_func(logger, 'info')
make_func(logger, 'notice')
make_func(logger, 'warning')
make_func(logger, 'error')
make_func(logger, 'fatal')

return logger
