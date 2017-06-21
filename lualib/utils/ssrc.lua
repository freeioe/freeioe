local sstack = require 'utils.sstack'

local class = {}

function class:alloc()
	return self._free:pop()
end

function class:free(ssrc)
	assert(ssrc >= 0)
	assert(ssrc < self._max)

	self._free:push(ssrc)
end

function class:init(count)
	self._free = sstack:Create()
	local stack = self._free
	local _et = stack._et
	for i = count - 1, 0, -1 do
		_et[#_et + 1] = i
	end
	assert(#_et == count)
end

return {
	new = function(count)
		local count = count or 10000
		local inst = setmetatable({_free=nil, _max=count}, {__index=class})
		inst:init(count)
		return inst
	end
}
