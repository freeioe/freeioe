local class = require 'middleclass'
local md5 = require 'md5'

local time = os.time
local format = string.format

local auth = class('freeioe.http.auth.digest')

--  see RFC-2617

function auth:initialize(user, passwd, realm, nonce, qop, algorithm, opaque)
	self._nc = 0
	self._user = assert(user)
	self._passwd = assert(passwd)
	self._realm = assert(realm)
	self._nonce = assert(nonce)
	self._qop = qop
	self._algorithm = algorithm or 'MD5'
	self._opaque = opaque
end

function auth:generate_nonce ()
    return format('%08x', time())
end

function auth:__call (headers, method, uri)
	self._nc = self._nc + 1
	local nc = format('%08X', self._nc)
	local cnonce = self:generate_nonce()
	local ha1, ha2, response
	ha1 = md5.sumhexa(self._user .. ':' .. self._realm .. ':' .. self._passwd)
	ha2 = md5.sumhexa(method .. ':' .. uri)
	if self._qop then
		response = md5.sumhexa(ha1 .. ':'
							  .. self._nonce .. ':'
							  .. nc .. ':'
							  .. cnonce .. ':'
							  .. self._qop .. ':'
							  .. ha2)
	else
		response = md5.sumhexa(ha1 .. ':'
							  .. self._nonce .. ':'
							  .. ha2)
	end
	local ret = 'Digest username="' .. self._user
			  .. '", realm="' .. self._realm
			  .. '", nonce="' .. self._nonce
			  .. '", uri="' .. uri
			  .. '", algorithm="' .. self._algorithm
			  .. '", nc=' .. nc
			  .. ', cnonce="' .. cnonce
			  .. '", response="' .. response

	if self._opaque then
		ret = ret .. '", opaque="' .. self.opaque .. '"'
	end

	if self._qop then
		ret = ret .. ', qop=' .. self._qop
	end

	return ret
end

return auth
