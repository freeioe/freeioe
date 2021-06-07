local class = require 'middleclass'
local crypt = require 'skynet.crypt'


local auth = class('freeioe.http.auth.basic')

-- Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==
--[[
local function gen_auth(auth)
	return 'Basic '..crypt.base64encode(auth[1]..':'..auth[2])
end
]]--

function auth:initialize(user, passwd)
	self._user = user
	self._passwd = passwd
end

function auth:__call (headers, method, uri)
	return 'Basic ' .. crypt.base64encode(self._user .. ':' .. self._passwd)
end

return auth
