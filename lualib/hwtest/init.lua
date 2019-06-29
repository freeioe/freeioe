local skynet = require 'skynet'
local class = require 'middleclass'
local log = require 'utils.log'

local test = class('FREEIOE_HWTEST_CLASS')

local function load_device(brand, device)
	local r, m = pcall(require, 'hwtest.devices.'..brand..'.'..device)
	if r then
		return m 
	end
	return nil, m
end

function test:initialize(brand, device)
	self._brand = brand
	self._device = device
	self._module = assert(load_device(brand, device))
	self._results = {}
end

local function protect_call(func, ...)
	assert(func)
	local r, er, err = xpcall(func, debug.traceback, ...)
	if not r then
		return nil, er and tostring(er) or nil
	end
	return er, er and tostring(err) or nil
end

function test:start()
	local tests = self._module.tests or {}

	for k, v in pairs(tests) do
		log.info("Run test case", k)
		self._results[k] = {
			name = k,
			finished = false,
		}
		skynet.fork(function()
			local r, err = protect_call(v, self)
			if not r then
				log.debug("Test "..k.." Failed", err)
			end
			self._results[k].finished = true
			self._results[k].result = r
			self._results[k].info = err or "Done"
		end)
	end
end

function test:finished()
	local all_done = true
	for k, v in pairs(self._results) do
		if not v.finished then
			return false
		end
		if not v.result  then
			all_done = false
		end
	end

	local finish = self._module.finish or function() end
	finish(all_done)

	return true
end

function test:result()
	return self._results
end

return test
