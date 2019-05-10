local class = require 'middleclass'

local buffer = class("APP_UTILS_STREAM_BUFFER")

function buffer:initialize(max_len)
	self._buf = {}
	self._droped = 0
	self._max_len = max_len
end

function buffer:concat()
	if #self._buf > 1 then
		local buf = table.concat(self._buf)
		--- Keep the buffer
		self._buf = { buf }
	end
	return self._buf[1]
end

function buffer:find(sk, ek)
	local buf = self:concat()

	if not buf or #buf == 0 then
		return nil, "Buffer empty"
	end

	if #buf <= #sk + (ek and #ek or 0) then
		return nil, "Buffer not enough"
	end

	--- Try to find start key
	local pos = string.find(buf, sk, 1, true)

	--- If there no is start key
	if not pos then
		--- Drop the noise data
		if #buf > #sk then
			if #sk > 1 then
				--- droped size
				self._droped = #buf - #sk
				buf = string.sub(buf, 0 - #sk)
				self._buf = { buf }
			else
				self._droped = #buf
				buf = nil
				self._buf = {}
			end
		end

		return nil, "Start key not found"
	else
		self._droped = pos - 1
		buf = string.sub(buf, pos)
		self._buf = { buf }
	end

	if not ek then
		return buf, #buf
	end

	local pos = string.find(buf, ek, string.len(sk) + 1, true)

	if pos then
		local len = pos + #ek
		local data = string.sub(buf, 1, len)
		self._buf = { data }
		if #data < #buf then
			self._buf[#self._buf + 1] = string.sub(buf, len + 1)
		end
		return data, len
	end

	if #buf > self._max_len then
		buf = string.sub(buf, 2)
		self._droped = self._droped + 1
		self._buf = { buf }
		return self:find(sk, ek)
	end

	return nil, "End key not found"
end

function buffer:pop(len)
	local data = self._buf[1]
	assert(data, "NO DATA CAN POP")

	if #data == len then
		table.remove(self._buf, 1)
		return
	end

	if #data > len then
		self._buf[1] = string.sub(data, len + 1)
	else
		local buf = table.concat(self._buf)

		if #buf <= len then
			self._buf = {}
		else
			self._buf = { string.sub(buf, len + 1) }
		end
	end
end

function buffer:len()
	local len = 0
	for _, v in ipairs(self._buf) do
		len = len + #v
	end
	return len
end

function buffer:droped()
	return self._droped
end

function buffer:append(data)
	self._buf[#self._buf + 1] = data
end

function buffer:clean()
	if #self._buf == 0 then
		return
	end

	local buf = self:concat()
	if not buf or #buf == 0 then
		self._buf = {}
		return
	end

	self._droped = self._droped + #buf
	self._buf = {}
end

return buffer
