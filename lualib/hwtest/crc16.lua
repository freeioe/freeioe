return function(adu)
	local crc;

	local function initCrc()
		crc = 0xffff;
	end
	local function updCrc(byte)
		if _VERSION == 'Lua 5.3' then
			crc = crc ~ byte
			for i = 1, 8 do
				local j = crc & 1
				crc = crc >> 1
				if j ~= 0 then
					crc = crc ~ 0xA001
				end
			end
		else
			local bit32 = require 'bit'
			crc = bit32.bxor(crc, byte);
			for i = 1, 8 do
				local j = bit32.band(crc, 1);
				crc = bit32.rshift(crc, 1);
				if j ~= 0 then
					crc = bit32.bxor(crc, 0xA001);
				end
			end
		end
	end

	local function getCrc(adu)
		initCrc();
		for i = 1, #adu  do
			updCrc(adu:byte(i));
		end
		return string.pack('I2', crc);
	end
	return getCrc(adu);
end

