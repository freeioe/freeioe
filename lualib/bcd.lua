--- Format
-- XXXX.XX six
-- nil - formating integer as its length
local _M = {}

local function unfold_format(format)
	return string.gsub(format, "([XxNn#])(%d+)", function(c, num)
		local ret = {}
		for i = 1, num do
			ret[#ret + 1] = c
		end
		return table.concat(ret)
	end)
end

function _M.encode(v, format)
	local format = unfold_format(format or ""):gsub('x', 'X'):gsub('n', 'N')
	--print(format)
	local int_s, float_s = string.match(format, '([XN#]*).?([XN#]*)')
	local len = string.len(int_s) + string.len(float_s)
	local float_len = string.len(float_s)

	if len == 0 then
		len = string.len(math.floor(v))
	else
		v = v % ( 10 ^ string.len(int_s))
	end

	if float_len > 0 then
		v = math.floor(v * (10 ^ float_len))
	end

	local ret = {}
	local len = math.ceil(len / 2)
	for i = 1, len do
		local val = math.floor(v % 100)
		ret[len + 1 - i] = string.char( (val // 10) * 16 + val % 10)
		v = v // 100
	end
	return table.concat(ret)
end

function _M.decode(str, format)
	local format = unfold_format(format or ""):gsub('x', 'X'):gsub('n', 'N')
	local int_s, float_s = string.match(format, '([XN#]*).?([XN#]*)')
	local int_len, float_len = string.len(int_s), string.len(float_s)

	local v = 0

	for i = 1, #str do
		local val = string.byte(str, i)
		v = v * 100 + (val // 16) * 10 + val % 16
	end

	if (int_len + float_len) > 0 then
		v = v % (10 ^ (int_len + float_len))
	end

	if float_len > 0 then
		v = v * (0.1 ^ float_len)
	else
		--- convert to integer if format has no .
		v = math.floor(v)
	end

	return v
end

function test()
	local bcd = _M -- require 'bcd'
	local basexx = require 'basexx'

	local function print_hex(str)
		print(basexx.to_hex(str))
	end

	print_hex(bcd.encode(1234567890.00231))
	print_hex(bcd.encode(-1234567890.00231))
	print_hex(bcd.encode(1234567890.00231, "X.XXXX"))
	print_hex(bcd.encode(1234567890.00231, "X.X4"))
	print_hex(bcd.encode(1234567890.00231, "X6.X4"))
	print_hex(bcd.encode(12345.21))
	print_hex(bcd.encode(-12345.21))
	print_hex(bcd.encode(tostring(123456.12)))
	print_hex(bcd.encode(tostring(12345.21)))
	local r = bcd.encode(string.format("%11d", 123456))
	print_hex(r)
	print(bcd.decode(r))
	print(bcd.decode(r, "XXX.XX"))
	print(bcd.decode(r, "X3.X2"))
end

--test()

return _M
