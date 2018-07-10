local dc = require 'skynet.datacenter'

local _M = {}

-- System ID
_M.id = function()
	return dc.get("CLOUD", "CLOUD_ID") or dc.wait("CLOUD", "ID")
end

_M.hw_id = function()
	return dc.wait("CLOUD", "ID")
end

return _M
