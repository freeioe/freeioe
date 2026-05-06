---
-- 端口辅助模块
--
-- 本模块提供Socket和串口数据读取的辅助功能
---

local _M = {}

---
-- 从Socket读取指定长度的数据
-- @tparam sock TCP Socket通道对象
-- @tparam len 需要的长度
-- @tparam dump 流转储函数。例如 function(str) print(str) end
function _M.read_socket(sock, len, dump)
	--local logger = require 'utils.logger'.new()
	--logger.trace('Start reading from socket stream. required len:', len)

	local str, err = sock:read(len)
	if not str then
		return nil, err
	end

	if dump then
		dump(str)
	end

	if string.len(str) >= len then
		return str
	end

	return nil, "The length of socket data is less than "..len.." LEN:"..string.len(str)
end

---
-- 从串口读取指定长度的数据
-- @tparam serial 串口通道对象
-- @tparam len 需要的长度
-- @tparam dump 流转储函数。例如 function(str) print(str) end
-- @tparam timeout 读取超时时间（毫秒）。默认为3000毫秒
function _M.read_serial(serial, len, dump, timeout)
	--local logger = require 'utils.logger'.new()
	--logger.trace('Start reading from serial port. required len:', len, 'timeout(ms):', timeout)

	local str, err = serial:read(len, timeout and timeout // 10 or nil)
	if not str then
		return nil, err
	end

	if dump then
		dump(str)
	end

	if string.len(str) >= len then
		return str
	end

	return nil, "The length of serial data is less than "..len.." LEN:"..string.len(str)
end

return _M
