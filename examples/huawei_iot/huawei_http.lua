local class = require 'middleclass'
local lcurl = require 'lcurl'
local cjson = require 'cjson.safe'

local api = class("HUAWEI_IOT_HTTP_API")

function api:initialize(sys, host, port, appid)
	assert(host and port and appid)
	self._sys = sys
	self._host = host
	self._port = port
	self._appid = appid
end

function api:post(url, body)
	local body = cjson.encode(body)
	local result = {}
	local easy_handle = lcurl.easy()
		:setopt_url("https://"..self._host..":"..self._port.."/iocm/dev/sec/v1.1.0/"..url)
		:setopt_writefunction(function(str) 
			result[#result + 1] = str
		end)
		:setopt_httpheader({"Content-Type: application/json"})
		:setopt_postfields(body)
		:setopt_ssl_verifyhost(0)
		:setopt_ssl_verifypeer(0)

	--easy_handle:perform()

	local m = lcurl.multi():add_handle(easy_handle)

	while m:perform() > 0 do
		self._sys:sleep(0)
		m:wait()
	end

	local h, r = m:info_read()
	easy_handle:close()
	if h ~= easy_handle or not r then
		return nil, "Failed to call login api"
	end

	local str = table.concat(result)
	return cjson.decode(str)

end

function api:login(device_id, secret)
	local body = {
		appId = self._appid,
		deviceId = device_id,
		secret = secret
	}
	return self:post("login", body)
end

function api:refresh_token(refresh_token)
	return self:post("refreshToken", {
		refreshToken = refresh_token
	})
end

return api
