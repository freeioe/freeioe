local unpack_table = table.unpack or unpack
local function retry(count, func, ...)
	local count = tonumber(count) or 0
	if count <= 0 then
		return func(...)
	end

	local args = {...}
	local rf = nil
	rf = function (r, ...)
		if not r and count > 0 then
			count = count - 1
			return rf(func(unpack_table(args)))
		end
		return r, ...
	end
	return rf(func(unpack_table(args)))
end

return retry
