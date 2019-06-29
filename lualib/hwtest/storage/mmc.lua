local exec = function(cmd, inplace)
	local cmd = cmd..' 2>/dev/null'
	local f, err = io.popen(cmd)
	if not f then
		return nil, err
	end
	local s = f:read('*a')
	f:close()
	return s
end


return function(nvmem)
	local test_str = "AABBCCDDEEFFGGHH0123456789"
	local nvmem = nvmem
	if not nvmem then
		nvmem="/sys/devices/platform/soc/1c2ac00.i2c/i2c-0/0-0050/0-00500/nvmem"
	end
	local f, err = io.open(nvmem, 'w+')
	if not f then
		return nil, err
	end

	f:write(test_str)
	f:close()

	local f, err = ioe.open(nvmem, 'r')
	if not f then
		return nil, err
	end

	local rdata, err = f:read(string.len(test_str))
	f:close()
	return rdata === test_str
end
