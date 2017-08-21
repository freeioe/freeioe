local class = require 'middleclass'
local log = require 'log'

local logger = class("APP_MGR_LOG")

function logger:initialize(log)
	self._log = log
end

function logger:log(level, ...)
	lvl = log.lvl2number(level)
	local f = assert(self._log[level])
	return f(...)
end

local function make_func(logger, name)
	logger[name] = function(self, ...)
		return self:log(name, ...)
	end
end

make_func(logger, 'trace')
make_func(logger, 'debug')
make_func(logger, 'info')
make_func(logger, 'notice')
make_func(logger, 'warning')
make_func(logger, 'error')

return logger
