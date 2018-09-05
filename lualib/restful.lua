local cjson = require 'cjson.safe'
local class = require 'middleclass'

local restful = class("RESTFULL_API")

function restful:initialize(host, timeout, headers)
	assert(host)
	self._host = host
	self._timeout = timeout or 5000
	self._headers = headers or {
		Accept = "application/json"
	}
end

local function init_httpc(timeout)
	local httpc = require 'http.httpc'

	--httpc.dns()
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

function restful:request(method, url, params, data)
	assert(url)

    local query = params or {}
	local recvheader = {}
	local content = data 
	if type(content) == 'table' then
		content = assert(cjson.encode(data))
	end

    local q = {}
    for k,v in pairs(query) do
        table.insert(q, string.format("%s=%s",escape(k),escape(v)))
    end
    if #q then
        url = url..'?'..table.concat(q, '&')
    end

	local httpc = init_httpc()

	local headers = {}
	for k, v in pairs(self._headers) do headers[k] = v end
	if content and string.len(content) > 0 then
		headers['content-type'] = headers['content-type'] or 'application/json'
	end

    local r, status, body = pcall(httpc.request, method, self._host, url, recvheader, headers, content)
	if not r then
		return nil, status
	else
		return status, body
	end
end

function restful:get(url, params, data)
	return self:request('GET', url, params, data)
end

function restful:post(url, params, data)
	return self:request('POST', url, params, data)
end

function restful:put(url, params, data)
	return self:request('PUT', url, params, data)
end

function restful:delete(url, params, data)
	return self:request('DELETE', url, params, data)
end

return restful
