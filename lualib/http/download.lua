local _M = {}

local function init_httpc(timeout)
	local httpc = require 'http.httpc'

	--httpc.dns()
	if timeout then
		httpc.timeout = timeout
	end
	return httpc
end

local function escape(s)
	if type(s) == 'boolean' then
		s = tostring(s)
	end
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

function _M.get(host, url, header, query, content)
	assert(host and url)
	if host:sub(1, 8) == 'https://' then
		return nil, "HTTPS is not supported"
	end
	if host:sub(1, 7) == 'http://' then
		host = host:sub(8)
	end
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
	-- print(url)

	local httpc = init_httpc()
    local r, status, body = pcall(httpc.request, 'GET', host, url, recvheader, header, content)
	if not r then
		return nil, status
	else
		if status == 301 or status == 302 then
			local location = recvheader.location or recvheader.Location
			if not location then
				return nil, 'Redirect location not found'
			end
			if location:sub(1,1) == '/' then
				return _M.get(host, location)
			else
				local host, port, url = location:match("([^:]+):?(%d*)//(.+)$")
				return _M.get(host..':'..port, url)
			end
		end
		return status, recvheader, body
	end
end

return _M
