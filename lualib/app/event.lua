--- 事件常量和工具模块
--
-- 本模块定义事件严重性级别和事件类型常量
-- 用于FreeIOE系统中的事件处理和报告
---


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

--- 将事件类型转换为字符串表示
-- @param type_: 事件类型数字或字符串
-- @return: 事件类型字符串（如"SYS"、"DEV"、"COMM"、"DATA"、"APP"）
---
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
