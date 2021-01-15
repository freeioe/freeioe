local skynet = require 'skynet'
local log = require 'utils.log'

local _M = {
	new = function(name)
		G_APP_NAME = G_APP_NAME or name
		local g_name = G_APP_NAME
		local LOG = {}
		for k, v in pairs(log) do
			local log_func = function (fmt, ...)
				local name = g_name or G_APP_NAME
				assert(name, "G_APP_NAME missing")
				return v('::'..name..':: '..fmt, ...)
			end

			LOG[k] = function(self, fmt, ...)
				if self == LOG then
					return log_func(fmt, ...)
				else
					return log_func(self, fmt, ...)
				end
			end
		end
		return LOG
	end
}

return _M
