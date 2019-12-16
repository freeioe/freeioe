local skynet = require 'skynet'
local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local class = require 'middleclass'

local conf = class("FREEIOE_APP_CONF_INIT")

local function load_defaults_real(filename)
	local f = assert(io.open(filename))
	local str = f:read('*a')
	local data = assert(cjson.decode(str))
	f:close()

	--- parse the json data
	
	local default = {}
	for _, v in ipairs(data) do
		if v.default ~= nil then
			default[v.name] = v.default
		end
	end

	return default
end

function conf:_load_defaults(filename)
	if 'file' ~= lfs.attributes(filename, 'mode') then
		return {}
	end

	local r, data = pcall(load_defaults_real, filename)
	if not r then
		self._log:error('Load app config file '..filename..' failed!', data)
		return {}
	else
		self._log:info('Loaded app config template file!!')
	end
	return data or {}
end

function conf:initialize(sys, conf_json)
	self._sys = sys
	self._log = sys:logger()
	self._conf_json = conf_json or 'conf.json'

	local filename = self._sys:app_dir()..'/'..self._conf_json
	self._default = self:_load_defaults(filename)

end

function conf:map(conf_t)
	return setmetatable(conf_t or {}, {__index = self._default})
end

function conf:__call(conf_t)
	return self:map(conf_t)
end

return conf
