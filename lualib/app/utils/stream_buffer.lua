---
-- 流缓冲区模块
--
-- 本模块提供用于模式匹配的流数据缓冲区。
-- 用于解析带有开始/结束标记的协议。
---

local class = require 'middleclass'

---
-- 流缓冲区类
--
-- 缓冲流数据并提取由开始和结束标记字符串分隔的数据包。
---
local buffer = class("APP_UTILS_STREAM_BUFFER")

---
-- 初始化流缓冲区
-- @param max_len: 强制清理前的最大缓冲区长度
---
function buffer:initialize(max_len)
	self._buf = {}
	self._droped = 0
	self._max_len = max_len
end

---
-- 将所有缓冲区块连接为单个字符串
-- @return: 连接后的缓冲区字符串
---
function buffer:concat()
	if #self._buf > 1 then
		local buf = table.concat(self._buf)
		--- 保留缓冲区
		self._buf = { buf }
	end
	return self._buf[1]
end

---
-- 查找由开始和结束键分隔的数据包
-- @param sk: 开始键字符串
-- @param ek: 结束键字符串（可选）
-- @return: 数据包数据和长度，或nil和错误信息
---
function buffer:find(sk, ek)
	local buf = self:concat()

	if not buf or #buf == 0 then
		return nil, "Buffer empty"
	end

	if #buf <= #sk + (ek and #ek or 0) then
		return nil, "Buffer not enough"
	end

	--- 尝试查找开始键
	local pos = string.find(buf, sk, 1, true)

	--- 如果没有开始键
	if not pos then
		--- 丢弃噪声数据
		if #buf > #sk then
			if #sk > 1 then
				--- 丢弃的大小
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

---
-- 从缓冲区弹出指定长度
-- @param len: 要移除的字节数
---
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

---
-- 获取当前缓冲区长度
-- @return: 缓冲区中的总字节数
---
function buffer:len()
	local len = 0
	for _, v in ipairs(self._buf) do
		len = len + #v
	end
	return len
end

---
-- 获取丢弃的字节数
-- @return: 丢弃的字节计数
---
function buffer:droped()
	return self._droped
end

---
-- 将数据块追加到缓冲区
-- @param data: 要追加的数据字符串
---
function buffer:append(data)
	self._buf[#self._buf + 1] = data
end

---
-- 清理所有缓冲区内容
-- 将所有当前数据标记为已丢弃
---
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
