local json = require 'cjson'
local class = require 'middleclass'

local _M = {}

local function init_httpc()
	local httpc = require 'http.httpc'

	httpc.dns()
	httpc.timeout = 10
	return httpc
end

local function escape(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

function _M.get(host, url, header, query, content)
	assert(host and url)
    local query = query or {}
    local header = header or {}
	local recvheader = {}

    local q = {}
    for k,v in pairs(query) do
        table.insert(q, string.format("%s=%s",escape(k),escape(v)))
    end
    if #q then
        url = url..'?'..table.concat(q, '&')
    end

	local httpc = init_httpc()
    local r, status, body = pcall(httpc.request, 'GET', host, url, recvheader, header, content)
	if not r then
		return nil, "failed call request"
	else
		return status, recvheader, body
	end
end

return _M
