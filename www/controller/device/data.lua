local dc = require 'skynet.datacenter'
local cjson = require 'cjson.safe'

local function load_device_data()
	local data = {}
	local devices = dc.get('DEVICES')
	for sn, props in pairs(devices) do
		if props.inputs then
			local inputs = dc.get('INPUT', sn) or {}
			for _, input in ipairs(props.inputs) do
				input.value = inputs[input.name] and inputs[input.name].value or {}
				if input.value.timestamp then
					--print(input.name, input.value.timestamp, type(input.value.timestamp))
					local ms = math.floor((input.value.timestamp % 1) * 1000)
					--input.value.timestamp = os.date('%F %T', math.floor(input.value.timestamp)) .. ' ' .. ms
					input.value.timestamp = os.date('%Y-%m-%d %H:%M:%S', math.floor(input.value.timestamp)) .. ' ' .. ms
				end
			end
		end
		if props.outputs then
			local outputs = dc.get('OUTPUT', sn) or {}
			for _, output in ipairs(props.outputs) do
				output.value = outputs[output.name] and outputs[output.name].value or {}
			end
		end
		data[#data + 1] = {
			sn = sn,
			props = props
		}
	end
	return data
end

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			return
		end
		local data = load_device_data()
		ngx.header.content_type = "application/json; charset=utf-8"
		ngx.print(cjson.encode({devices=data}))
	end
}
