local class = require 'middleclass'
local skynet = require 'skynet'
local conf_api = require 'app.conf_api'
local log = require 'utils.log'

local helper = class("APP_CONF_API_HELPER")

function helper:initialize(sys_api, conf, templates_ext, templates_dir, templates_node, devices_node)
	self._sys = sys_api
	self._conf = conf or {}
	self._templates_ext = templates_ext or "csv"
	self._templates_dir = templates_dir or "tpl"
	self._templates_node = templates_node or "tpls"
	self._devices_node = devices_node or "devs"

	self._templates = {}
	self._devices = {}
end

function helper:_real_fetch()
	local templates = self._conf[self._templates_node] or {}
	local devices = self._conf[self._devices_node] or {}

	while true do
		local not_finished = false
		for _, tpl in ipairs(templates) do
			if not self._templates[tpl.name] then
				local r, version = self:download_tpl(tpl)
				if r and version == tonumber(tpl.ver) then
					self._templates[tpl.name] = {
						id = tpl.id,
						name = tpl.name,
						ver = tpl.ver,
						data = r
					}
				else
					not_finished = true
					log.warning('Cannot fetch app_conf', version)
				end
			end
		end
		for _, dev in ipairs(devices) do
			if not self._devices[dev.name] then
				if self._templates[dev.tpl] then
					log.debug(string.format('Device [%s] with template [%s] is ready!!', dev.name, dev.tpl))
					self._devices[dev.name] = dev
				else
					log.warning(string.format('Cannot create device [%s] as template [%s] is not ready', dev.name, dev.tpl))
				end
			end
		end
		if not_finished then
			skynet.sleep(500)
		else
			break
		end
	end
end

function helper:fetch(async)
	if not async then
		return self:_real_fetch()
	else
		skynet.fork(function()
			self:_real_fetch()
		end)
	end
end

function helper:templates()
	local templates = {}
	for _, v in ipairs(self._conf[self._templates_node] or {}) do
		table.insert(templates, self._templates[v.name])
	end
	return templates
end

function helper:devices()
	local devices = {}
	for _, v in ipairs(self._conf[self._devices_node] or {}) do
		table.insert(devices, self._devices[v.name])
	end
	return devices
end

function helper:download_tpl(tpl)
	log.debug("conf_helper download template", tpl.id, tpl.name, tpl.ver)
	local api = self._sys:conf_api(tpl.id, self._templates_ext, self._templates_dir)
	local data, version = api:data(tpl.ver)
	if not data then
		return nil, version
	end
	local path = self._sys:app_dir()..self._templates_dir.."/"..tpl.name.."."..self._templates_ext
	local f, err = io.open(path, "w+")
	if not f then
		return nil, err
	end
	f:write(data)
	f:close()
	return true, tonumber(version)
end

return helper
