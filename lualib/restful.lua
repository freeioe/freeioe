local json = require 'cjson'
local class = require 'middleclass'

local restful = class("RESTFULL_API")

function restful:initialize(host, timeout, headers)
	assert(host)
	self._host = host
	self._timeout = timeout or 5000
	self._headers = headers or {}
end

local function init_httpc(timeout)
	local httpc = require 'http.httpc'

	httpc.dns()
	if timeout then
		httpc.timeout = timeout / 10
	end
	return httpc
end

local function escape(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

function restful:request(method, url, params, query)
	assert(url)

    local query = query or {}
	local recvheader = {}
	local content = params
	if type(content) == 'table' then
		content = cjson.encode(params)
	end

    local q = {}
    for k,v in pairs(query) do
        table.insert(q, string.format("%s=%s",escape(k),escape(v)))
    end
    if #q then
        url = url..'?'..table.concat(q, '&')
    end

	local httpc = init_httpc()
    local r, status, body = pcall(httpc.request, method, host, url, recvheader, self._headers, content)
	if not r then
		return nil, status
	else
		return status, body
	end
end

function restful:get(url, params, query)
	return self:request('GET', url, params, query)
end

function restful:post(url, params, query)
	return self:request('POST', url, params, query)
end

function restful:put(url, params, query)
	return self:request('PUT', url, params, query)
end

function restful:delete(url, params, query)
	return self:request('DELETE', url, params, query)
end

return restful
