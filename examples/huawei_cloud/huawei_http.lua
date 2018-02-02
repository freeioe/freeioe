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
	self._access_token = nil
end

function api:set_access_token(token)
	self._access_token = token
end

function api:post(url, body, oauth)
	local body = cjson.encode(body)
	local result = {}
	local header = {
		"Content-Type: application/json",
	}
	if oauth then
		header[#header + 1] = "Authorization:Bearer "..self._access_token
	end

	local easy_handle = lcurl.easy()
		:setopt_url("https://"..self._host..":"..self._port.."/"..url)
		:setopt_writefunction(function(str) 
			--print("R:", str)
			result[#result + 1] = str
		end)
		:setopt_httpheader(header)
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
	return self:post("iocm/dev/sec/v1.1.0/login", body)
end

function api:refresh_token(refresh_token)
	return self:post("iocm/dev/sec/v1.1.0/refreshToken", {
		refreshToken = refresh_token
	})
end

function api:sync_devices(devices)
	local deviceInfos = {}
	for sn, props in pairs(devices) do
		deviceInfos[#deviceInfos + 1] = {
			nodeId = sn,
			name = sn,
			manufacturerId = "SymTech",
			deviceType = "MultiSensor",
			model = "WhoKnows",
			prootocolType = "WIFI"
		}
	end
	return self:post("iocm/dev/dm/v1.1.0/devices/sync", {deviceInfos = deviceInfos}, true)
end

return api
