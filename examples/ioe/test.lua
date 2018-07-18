local cjson = require 'cjson'
local net = require 'netstat'

local info = net.net_dev('lo')
print(cjson.encode(info))
if #info == 16 then
	print(info[1], info[9])
end
