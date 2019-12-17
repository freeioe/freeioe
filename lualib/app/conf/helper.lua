local class = require 'middleclass'
local skynet = require 'skynet'
local log = require 'utils.log'
local cjson = require 'cjson.safe'

local helper = class("FREEIOE_APP_CONF_API_HELPER")

function helper:initialize(sys_api, conf, templates_ext, templates_dir, templates_node, devices_node)
	assert(sys_api and conf)
	self._sys = sys_api
	self._log = sys_api:logger()
	self._conf = conf
	self._templates_ext = templates_ext or "csv"
	self._templates_dir = templates_dir or "tpl"
	self._templates_node = templates_node or "tpls"
	self._devices_node = devices_node or "devs"

	self._templates = {}
	self._devices = {}

	if not lfs.attributes(self._templates_dir, "mode") then
		lfs.mkdir(self._templates_dir)
	end
end

function helper:_load_conf()
	local conf_name, version = string.match(self._conf, "([^%.]+).(%d+)")
	conf_name = conf_name or self._conf
	version = math.tointeger(version)

	local api = self._sys:conf_api(conf_name, "cnf", self._templates_dir)

	--- Fetch latest version
	if not version then
		local ver, err = api:version()
		if not ver then
			self._log:warning("Get cloud configuration version failed", err)
			return {}
		end
		version = ver
	end

	--- Fetch configuration now!
	self._log:notice("Loading cloud configuration", conf_name, version)

	local config, err = api:data(version)
	if not config then
		self._log:warning("Cloud configuration loading failed", err)
		return {}
	end
	-- Decode as json
	local conf, err = cjson.decode(config)
	if not conf then
		self._log:error("Cloud configuration decode error: "..err)
		return {}
	end
	return conf
end

function helper:_real_fetch()
	if type(self._conf) == 'string' then
		self._conf = self:_load_conf()
	end

	local templates = self._conf[self._templates_node] or {}
	local devices = self._conf[self._devices_node] or {}

	if #templates == 0 then
		self._log:warning('Cannot detect template list from configuration, by node name', self._templates_node)
		for _, dev in ipairs(devices) do
			self._devices[dev.name] = dev
		end
		return
	end

	while true do
		local not_finished = false
		for _, tpl in ipairs(templates) do
			if not self._templates[tpl.name] then
				local r, version = self:_download_tpl(tpl)
				if r and version == tonumber(tpl.ver) then
					self._log:info('download template finished. template:', tpl.id, tpl.ver)
					self._templates[tpl.name] = {
						id = tpl.id,
						name = tpl.name,
						ver = tpl.ver,
						data = r
					}
				else
					not_finished = true
					self._log:warning('Cannot fetch template', version)
				end
			end
		end
		for _, dev in ipairs(devices) do
			if not self._devices[dev.name] then
				if self._templates[dev.tpl] then
					self._log:info(string.format('Device [%s] with template [%s] is ready!!', dev.name, dev.tpl))
					self._devices[dev.name] = dev
				else
					self._log:warning(string.format('Cannot create device [%s] as template [%s] is not ready', dev.name, dev.tpl))
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

function helper:config()
	return self._conf
end

function helper:templates()
	local templates = {}
	for _, v in ipairs(self._conf[self._templates_node] or {}) do
		local tpl = self.templates[v.name]
		if tpl then
			table.insert(templates, tpl)
		end
	end
	return templates
end

function helper:devices()
	local devices = {}
	for _, v in ipairs(self._conf[self._devices_node] or {}) do
		local dev = self._devices[v.name]
		if dev then
			table.insert(devices, dev)
		end
	end
	return devices
end

function helper:_download_tpl(tpl)
	self._log:debug("conf_helper download template", tpl.id, tpl.name, tpl.ver)
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
