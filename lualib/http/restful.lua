local cjson = require 'cjson.safe'
local class = require 'middleclass'
local crypt = require "skynet.crypt"
local basic_auth = require 'http.auth.basic'

local restful = class("RESTFULL_API")

function restful:initialize(host, timeout, headers, auth)
	assert(host)
	self._host = host
	self._timeout = timeout or 5000
	self._headers = headers or {
		Accept = "application/json",
	}
	if auth then
		if type(auth) == 'table' and not getmetatable(auth) then
			self._auth = basic_auth:new(auth[1], auth[2])
		else
			self._auth = auth
		end
	end
end

local function init_httpc(timeout)
	local httpc = require 'http.httpc'

	--httpc.dns()
	if timeout then
		httpc.timeout = timeout / 10
	else
		httpc.timeout = nil
	end
	return httpc
end

local function escape(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

function restful:request(method, url, params, data, content_type)
	assert(url)

    local query = params or {}
	local recvheader = {}
	local content = data 
	local ctype = content_type or 'text/plain'
	if type(content) == 'table' then
		content = assert(cjson.encode(data))
		ctype = 'application/json'
	end

    local q = {}
    for k,v in pairs(query) do
        table.insert(q, string.format("%s=%s",escape(k),escape(v)))
    end
    if #q > 0 then
        url = url..'?'..table.concat(q, '&')
    end

	-- Set the timeout and get httpc
	local httpc = init_httpc(self._timeout)

	local headers = {}
	for k, v in pairs(self._headers) do headers[k] = v end
	if content and string.len(content) > 0 then
		headers['content-type'] = ctype
	end

	if self._auth then
		headers['authorization'] = self._auth(headers, method, url)
	end

    local r, status, body = pcall(httpc.request, method, self._host, url, recvheader, headers, content)

	-- Reset the timeout
	httpc.timeout = nil

	if not r then
		return nil, status
	else
		return status, body, recvheader
	end
end

function restful:get(url, params, data, conent_type)
	return self:request('GET', url, params, data, conent_type)
end

function restful:post(url, params, data, conent_type)
	return self:request('POST', url, params, data, conent_type)
end

function restful:put(url, params, data, conent_type)
	return self:request('PUT', url, params, data, conent_type)
end

function restful:delete(url, params, data, conent_type)
	return self:request('DELETE', url, params, data, conent_type)
end

return restful
