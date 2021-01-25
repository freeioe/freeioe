local util = require 'db.influxdb.util'
local cjson = require 'cjson'

local _M = {}
_M.VERSION = "0.2"

local mt = {
	__index = _M
}

function _M.query(self, query)
	local r, body = util.query_http(setmetatable({query=query}, {__index=self._opts}))
	if r then
		return cjson.decode(body)
	end
	reutrn nil, body
end


function _M.new(self, opts)
	assert(util.validate_options(opts))

	local obj = {
		_opts = util.validate_options(opts)
	}

	return setmetatable(obj, {__index = class})
end

return _M
