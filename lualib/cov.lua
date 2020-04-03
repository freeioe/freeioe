local class = require 'middleclass'
local skynet = require 'skynet'
local coroutine = require 'skynet.coroutine'
local ioe = require 'ioe'

local cov = class("_ChangeOnValue_LIB")

function cov:initialize(cb, opt)
	assert(cb)
	local opt = opt or {}

	opt.float_threshold = opt.float_threshold or 0.000001
	opt.try_convert_string = false

	opt.ttl = tonumber(opt.ttl)
	if opt.ttl and opt.ttl <= 0 then
		opt.ttl = nil
	end
	opt.min_ttl_gap = opt.min_ttl_gap or 10  -- 0.1 seconds

	self._cb = cb
	self._opt = opt
	self._retained_map = {}

	self._stop = nil
end

function cov:clean()
	self._retained_map = {}
end

function cov:clean_with_match(mfunc)
	for key, v in pairs(self._retained_map) do
		if mfunc(key) then
			self._retained_map[key] = nil
		end
	end
end

function cov:handle_number(key, value, timestamp, quality, nomore)
	assert(nomore==nil)
	local opt = self._opt
	local org_value = self._retained_map[key]
	local new_value = {value, timestamp, quality}
	self._retained_map[key] = new_value

	if not org_value then
		return self._cb(key, value, timestamp, quality)
	end
	if opt.ttl and ((timestamp - org_value[2]) >= opt.ttl) then
		return self._cb(key, value, timestamp, quality)
	end
	if org_value[3] ~= quality then
		return self._cb(key, value, timestamp, quality)
	end
	if math.abs(value - org_value[1]) > opt.float_threshold then
		return self._cb(key, value, timestamp, quality)
	end

	self._retained_map[key] = org_value
end

function cov:handle_string(key, value, timestamp, quality, nomore)
	assert(nomore==nil)
	local opt = self._opt
	local org_value = self._retained_map[key]
	local new_value = {value, timestamp, quality}
	self._retained_map[key] = new_value

	if not org_value then
		return self._cb(key, value, timestamp, quality)
	end
	if opt.ttl and ((timestamp - org_value[2]) >= opt.ttl) then
		return self._cb(key, value, timestamp, quality)
	end
	if org_value[3] ~= quality then
		return self._cb(key, value, timestamp, quality)
	end
	if value ~= org_value[1] then
		return self._cb(key, value, timestamp, quality)
	end

	self._retained_map[key] = org_value
end

function cov:handle(key, value, timestamp, quality, nomore)
	assert(nomore==nil)
	assert(key and value and timestamp)
	local opt = self._opt
	if opt.disable then
		return self._cb(key, value, timestamp, quality)
	end

	if type(value) == 'number' then
		return self:handle_number(key, value, timestamp, quality)
	else
		if opt.try_convert_string then
			local nval = tonumber(value)
			if nval then
				return self:handle_number(key, value, timestamp, quality)
			end
		end
		return self:handle_string(key, value, timestamp, quality)
	end
end

function cov:fire_snapshot(cb)
	local cb = cb or self._cb
	for key, v in pairs(self._retained_map) do
		cb(key, table.unpack(v))
	end
end

--- Call this timer function manually if you won't using start/stop method
-- @tparam now number Skynet time in seconds ( float )
-- @tparam cb function  Callback function for fire data out
-- @treturn number Skynet time in seconds ( float )
function cov:timer(now, cb)
	local cb = cb or self._cb
	local opt = self._opt
	local opt_ttl = opt.ttl
	local next_loop = opt_ttl
	-- Loop all inputs
	for key, v in pairs(self._retained_map) do
		-- Get current input next ttl fire time gap
		local tv = v[2]
		local quality = v[3] or 0
		local gap = opt_ttl - math.abs(now - tv)
		-- Fire data if reached the ttl
		if quality == 0 and gap <= 0 then
			v[2] = now
			local r = cb(key, table.unpack(v))	
			if not r then
				--- Currently we skip this update???
				--- v[2] = tv
			end
			self._retained_map[key] = v
		end
		-- return min next time gap
		if quality == 0 and gap > 0 and next_loop > gap then
			next_loop = gap
		end
	end
	--return math.floor(next_loop)
	return next_loop
end

function cov:start(no_param)
	assert(no_param == nil)
	if not self._opt.ttl then
		return
	end

	self._stop = nil
	local min_ttl_gap = self._opt.min_ttl_gap
	skynet.fork(function()
		while not self._stop do
			local gap = self:timer(ioe.time(), self._cb)
			gap = math.floor(gap * 100)
			if gap < min_ttl_gap then
				gap = min_ttl_gap
			end
			skynet.sleep(gap, self)
		end
	end)
end

function cov:stop()
	if not self._stop then
		self._stop = true
		skynet.wakeup(self)
	end
end

return cov
