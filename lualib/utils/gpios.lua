local skynet = require 'skynet'
local sysinfo = require 'utils.sysinfo'
local lfs = require 'lfs'
local cancelable_timeout = require 'cancelable_timeout'

local class = {}

local function list_gpios()
	local list = {}
	local os_id = sysinfo.os_id()
	if os_id == 'openwrt' then
		local gpios_path = '/sys/class/gpio'
		if lfs.attributes(gpios_path, 'mode') == 'directory' then
			for filename in lfs.dir(gpios_path) do
				local value_path = gpios_path.."/"..filename.."/value",
				-- export, unexport file are not gpio folder
				if filename ~= 'export' and filename ~= 'unexport' and lfs.attributes(value_path, 'mode') == 'file' then
					list[filename] = {
						name = filename,
						value_path = value_path,
					}
				end
			end
		end
	end
	return list
end

local function find_gpio(gpios, name)
	if gpios[name] then
		return name
	end
	return nil, "Not found"
end

local gpio_class = {}

function gpio_class:value(value)
	if value then
		os.execute("echo "..tostring(value).." > "..self.value_path)
		return value
	else
		local f, err = io.open(self.value_path)
		if not f then
			return nil, err
		end
		local value = f:read("*a")
		f:close()
		return value
	end
end

function gpio_class:toggle()
	local value = self:value()
	if value == 0 then
		return self:value(1)
	else
		return self:value(0)
	end
end

function gpio_class:cancel_blink()
	if self._cancel_blink then
		self._cancel_blink()
		self._cancel_blink = nil
	end
end

function gpio_class:blink(sec, dark_sec)
	self:cancel_blink()
	if not sec then
		return
	end

	local blink_func = nil
	local blink_state = 1
	local blink_timeout = math.floor(sec * 100)

	blink_func = function()
		self:value(blink_state)
		blink_state = blink_state == 0 and 1 or 0

		local timeout = blink_timeout
		if dard_sec ~= nil and blink_state == 0 then
			timeout = math.floor(dark_sec * 100)
		end
		self._cancel_trigger = cancelable_timeout(timeout, blink_func)
	end

	blink_func()
end

local function create_gpio_obj(gpios, name)
	local gpio = gpios[name]

	return setmetatable(gpio, {__index = gpio_class})
end

local function create_gpios()
	local obj = {}
	obj._gpios = list_gpios()
	return setmetatable(obj, {__index=function(t, k)
		local name = find_gpio(t._gpios, k)
		if not name then
			return nil
		end

		local gpio = create_gpio_obj(t._gpios, name)
		t[k] = gpio
		return gpio
	end})
end

local _M = create_gpios()

return _M
