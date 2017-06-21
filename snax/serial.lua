local skynet = require 'skynet'
local driver = require 'serialdriver'

local port = nil

function response.open(cb)
	local r, err = port:open()
	if not r then
		return nil, tostring(err)
	end
	local cb = cb or function(data, err)
		print('RECV', port:fd(), data, err)
	end
	port:start(cb)
	return true
end

function response.write(data)
	return port:write(data)
end

function init(port_name, ...)
	skynet.error("SNAX.SERIAL created", port_name, ...)
	port = assert(driver:new(port_name))
end

function exit(...)
	port:stop()
end
