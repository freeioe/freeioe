local class = require 'middleclass'

local cb = class("_CycleBuffer_LIB")

function cb:initialize(size, name)
	self._max_size = size
	self._name = name or "unknown cycle buffer"
	self._buf = {}
end

function cb:handle(cb, ...)
	local buf = self._buf
	local ne = true
	if #buf > 0 then
		local nbuf = {}
		for _, v in ipairs(buf) do
			if ne and cb(table.unpack(v)) then
				--
			else
				ne = false
				nbuf[#nbuf + 1] = v
			end
		end
		buf = nbuf
	end

	if ne and cb(...) then
		self._buf = buf
		return
	end

	buf[#buf + 1] = {...}
	if #buf > self._max_size then
		table.remove(buf, 1)	
	end
	self._buf = buf
end

function cb:size()
	return #self._buf
end

return cb
