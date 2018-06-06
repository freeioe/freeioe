local class = require 'middleclass'
local cjson = require 'cjson.safe'

local tpl = class("FREEIOE_SYS_TPL_CLASS")

local tpls = {
	{
		-- if name start with * (e.g. *device) then option is required for configuration to have multiple device for this template
		name = "ioe", 
		desc = "System Information Statistics",
		input = {
			cpuload = "Upload device cpu-load every minutes",
			uptime = "Upload device uptime every minutes",
			startime = "Upload device start-time every minutes",
		},
		output = {
		},
		command = {
			reboot = "Reboot System"
		},
		--option = {}
	},
}

function tpl:list_tpl()
	return tpls
end

function tpl:initialize()
	self._disabled = {}
end

function tpl:option()
	return {
		--configurable = true, -- default is not configruable
		selectable = true
	}
end

function tpl:enable_input(name, input, enable)
	if name ~= 'ioe' then
		return nil, "No such device"
	end
	self._disabled[input] = enable and true or nil
end

function tpl:enable_output(name, output, enable)
	return nil, "No output"
end

function tpl:enable_command(name, command, enable)
	if name ~= 'ioe' or command ~= 'reboot' then
		return nil, "No such device"
	end
	self._disable_reboot = enable and true or nil
end

function tpl:dumps()
	return cjson.encode({
		disable_reboot = self._disable_reboot,
		disabled = self._disabled
	})
end

function tpl:loads(str)
	local o = cjson.decode(str)
	self._disable_reboot = o.disable_reboot
	self._disabled = o.disabled
end

function tpl:add_device(tpl, name, sn)
	if tpl:sub(1,1) ~= '*' then
		return nil, "Device cannot be added, as "..tpl.." is not multiple-instance template"
	end
end

function tpl:del_device(name)
end

return tpl
