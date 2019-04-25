local class = require 'middleclass'

local cb = class("_CycleBuffer_LIB")

function cb:initialize(size)
	assert(size)
	self._max_size = size
	self._buf = {}
end

function cb:handle(cb, ...)
	local ne = self:fire_all(cb)
	if ne and cb(...) then
		return
	end

	self._buf[#self._buf + 1] = {...}
	if #self._buf > self._max_size then
		table.remove(self._buf, 1)	
	end
end

function cb:fire_all(cb)
	local buf = self._buf
	local ne = true
	if #buf <= 0 then
		return true
	end

	local nbuf = {}
	for _, v in ipairs(buf) do
		if ne and cb(table.unpack(v)) then
			--
		else
			ne = false
			nbuf[#nbuf + 1] = v
		end
	end
	self._buf = nbuf
	return ne
end

function cb:size()
	return #self._buf
end

return cb
