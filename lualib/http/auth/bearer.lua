local class = require 'middleclass'


local auth = class('freeioe.http.auth.bearer')


function auth:initialize(token)
	self._bearer_token = assert(token)
end

function auth:__call(headers, method, uri)
	return 'Bearer ' .. self._bearer_token
end

return auth
