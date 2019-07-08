local skynet = require 'skynet'
local sysinfo = require 'utils.sysinfo'
local lfs = require 'lfs'
local cancelable_timeout = require 'cancelable_timeout'

local class = {}

local function list_leds()
	local list = {}
	local os_id = sysinfo.os_id()
	if os_id == 'openwrt' then
		local leds_path = '/sys/class/leds'
		if lfs.attributes(leds_path, 'mode') == 'directory' then
			for filename in lfs.dir(leds_path) do
				local id, color, short_name = string.match(filename, '^([^:]+):([^:]+):([^:]+)$')
				list[filename] = {
					name = filename,
					brightness_path = leds_path.."/"..filename.."/brightness",
					id = id,
					color = color,
					short_name = short_name,
				}
			end
		end
	end
	return list
end

local function find_led(leds, name)
	if leds[name] then
		return name
	end
	for k, v in pairs(leds) do
		if v.short_name == name then
			return k
		end
	end
	return nil, "Not found"
end

local led_class = {}

function led_class:brightness(value)
	if value then
		os.execute("echo "..tostring(value).." > "..self.brightness_path)
		return value
	else
		local f, err = io.open(self.brightness_path)
		if not f then
			return nil, err
		end
		local value = f:read("*a")
		f:close()
		return value
	end
end

function led_class:toggle()
	local value = self:brightness()
	if value == 0 then
		return self:brightness(1)
	else
		return self:brightness(0)
	end
end

function led_class:cancel_blink()
	if self._cancel_blink then
		self._cancel_blink()
		self._cancel_blink = nil
	end
end

function led_class:blink(sec, dark_sec)
	self:cancel_blink()
	if not sec then
		return
	end

	local blink_func = nil
	local blink_state = 1
	local blink_timeout = math.floor(sec * 100)

	blink_func = function()
		self:brightness(blink_state)
		blink_state = blink_state == 0 and 1 or 0

		local timeout = blink_timeout
		if dard_sec ~= nil and blink_state == 0 then
			timeout = math.floor(dark_sec * 100)
		end
		self._cancel_blink = cancelable_timeout(timeout, blink_func)
	end

	blink_func()
end

local function create_led_obj(leds, name)
	local led = leds[name]

	return setmetatable(led, {__index = led_class})
end

local function create_leds()
	local obj = {}
	obj._leds = list_leds()
	return setmetatable(obj, {__index=function(t, k)
		local name = find_led(t._leds, k)
		if not name then
			return nil
		end

		local led = create_led_obj(t._leds, name)
		t[k] = led
		return led
	end})
end

local _M = create_leds()

return _M
