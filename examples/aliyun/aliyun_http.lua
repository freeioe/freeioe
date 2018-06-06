local class = require 'middleclass'
local lcurl = require 'lcurl'
local cjson = require 'cjson.safe'
local sha1 = require 'hashings.sha1'
local md5 = require 'hashings.md5'
local hmac = require 'hashings.hmac'

local api = class("ALIYUN_HTTPS_API")

function api:initialize(sys, host, product_key)
	self._sys = sys
	self._host = host
	self._product_key = product_key
end

function api:gen_sign(device_name, device_secret, client_id, timestamp)
	local content = table.concat({
		"clientId", client_id,
		"deviceName", device_name,
		"productKey", self._product_key,
		"timestamp", timestamp
	})
	local sign = hmac:new(sha1, device_secret, content):hexdigest()
	--print(device_secret, content, sign)
	return sign
end

function api:gen_sign_md5(device_name, device_secret, client_id, timestamp)
	local content = table.concat({
		"clientId", client_id,
		"deviceName", device_name,
		"productKey", self._product_key,
		"timestamp", timestamp
	})
	local sign = hmac:new(md5, device_secret, content):hexdigest()
	--print(device_secret, content, sign)
	return sign
end

function api:auth(device_name, device_secret, client_id)
	local result = {}
	local headers = {}
	local timestamp = os.time() * 1000
	local sign = self:gen_sign(device_name, device_secret, client_id, timestamp)
	local body = table.concat({
		"productKey="..self._product_key,
		"deviceName="..device_name,
		"sign="..sign,
		"signmethod=hmacsha1",
		"clientId="..client_id,
		"timestamp="..timestamp,
		"resources=mqtt",
		"version=default"
	}, "&")
	--print(body)

	local easy_handle = lcurl.easy()
		:setopt_url("https://"..self._host.."/auth/devicename")
		:setopt_httpheader({"Content-Type: application/x-www-form-urlencoded"})
		:setopt_postfields(body)
		:setopt_writefunction(function(str) 
			--print("R:", str)
			result[#result + 1] = str
		end)
		:setopt_headerfunction(function(str)
			--print("H:", str)
			headers[#headers + 1] = str
		end)
	
	local m = lcurl.multi():add_handle(easy_handle)

	while m:perform() > 0 do
		self._sys:sleep(0)
		m:wait()
	end

	local h, r = m:info_read()
	easy_handle:close()
	if h ~= easy_handle or not r then
		return nil, "Failed to perform request"
	end

	local hstr = table.concat(headers)
	local str = table.concat(result)

	local code = string.match(hstr, "^HTTP/1.1 (%d+)")
	if tonumber(code) ~= 200 then
		return nil, hstr..str
	end

	local r, err = cjson.decode(str)
	if not r then
		return nil, err
	end

	if r.code == 200 then
		return r.data
	end
	return nil, r.message
end

return api
