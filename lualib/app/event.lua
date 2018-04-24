
local EVENTS = {
	EVENT_SYS = 1,
	EVENT_DEV = 2,
	EVENT_COMM = 3,
	EVENT_DATA = 4,
	EVENT_APP = 5,
}
local LEVELS = {
	LEVEL_DEBUG = 0,
	LEVEL_INFO = 1,
	LEVEL_WARNING = 2,
	LEVEL_ERROR = 3,
	LEVEL_FATAL = 99,
}
local EVENT_NAMES = {
	"系统",
	"设备",
	"通讯",
	"数据",
	"应用",
}

local function type_to_string(type_)
	if type(type_) == 'number' then
		assert(type_ > 0 and type_ < #EVENTS)
		return EVENTS[type_ - 1]
	else
		return type_
	end
end

local _M = {}
for k,v in pairs(EVENTS) do
	_M[k] = v
end

for k,v in pairs(LEVELS) do
	_M[k] = v
end

_M.type_to_string = type_to_string

return _M

