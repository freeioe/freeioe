local class = require 'middleclass'
local skynet = require 'skynet'
local conf_api = require 'app.conf_api'
local log = require 'utils.log'

local helper = class("APP_CONF_API_HELPER")

function helper:initialize(conf, templates_node, devices_node)
	self._conf = conf or {}
	self._templates = {}
	self._devices = {}
	self._templates_node = templates_node or "tpls"
	self._devices_node = devices_node or "devs"
end

function helper:_real_fetch()
	local templates = self._conf[self._templates_node] or {}
	local devices = self._conf[self._devices_node] or {}
	while true do
		for _, tpl in ipairs(templates) do
			if not self._templates[tpl.name] then
				local val, version = self:download_tpl(tpl.id, tpl.ver)
				if val and version == tpl.ver then
					self._templates[tpl.name] = {
						id = tpl.id,
						name = tpl.name,
						ver = tpl.ver,
						data = r
					}
				else
					log.warning('Cannot fetch app_conf', version)
				end
			end
		end
		for _, dev in ipairs(devices) do
			if not self._devices[dev.name] then
				if self._templates[dev.tpl] then
					self._devices[dev.name] = dev
				end
			end
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
	return self._templates
end

function helper:devices()
	return self._devices
end
