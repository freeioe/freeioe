
local LEVELS = {
	LEVEL_DEBUG = 0,
	LEVEL_INFO = 1,
	LEVEL_WARNING = 2,
	LEVEL_ERROR = 3,
	LEVEL_FATAL = 99,
}

local EVENTS = {
	'EVENT_SYS',
	'EVENT_DEV',
	'EVENT_COMM',
	'EVENT_DATA',
	'EVENT_APP',
}

--[[
local EVENT_NAMES = {
	"系统",
	"设备",
	"通讯",
	"数据",
	"应用",
}
]]--
local EVENT_NAMES = {}

local function type_to_string(type_)
	if type(type_) == 'number' then
		assert(type_ > 0 and type_ <= #EVENTS)
		return EVENT_NAMES[type_]
	else
		return type_
	end
end

local _M = {}
for i,v in ipairs(EVENTS) do
	_M[v] = i
	EVENT_NAMES[i] = string.sub(v, string.len('EVENT_') + 1)
end

for k,v in pairs(LEVELS) do
	_M[k] = v
end

_M.type_to_string = type_to_string

return _M

