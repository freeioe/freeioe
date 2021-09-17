local datacenter = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local httpdown = require 'http.download'
local class = require 'middleclass'
local pkg_api = require 'pkg.api'
local ioe = require 'ioe'
local lfs = require 'lfs'

local api = class("FREEIOE_APP_CONF_CENTER_API")

local api_header = {
	Accpet = "application/json"
}

--- Constructor
-- @tparam string app Application ID
-- @tparam string conf Application configuration id
-- @tparam string ext Local saving file extension. e.g. csv conf xml. default csv
-- @tparam string dir Application template file saving directory. full path.
function api:initialize(sys, app, conf, ext, dir)
	-- Service host (ip or domain)
	self._host = ioe.cnf_host_url()
	self._sys = sys
	self._app = app
	self._log = sys:logger()
	self._conf = conf
	self._ext = ext or 'csv'
	self._dir = dir or 'tpl'
	if not lfs.attributes(self._dir, "mode") then
		lfs.mkdir(self._dir)
	end
end

---
-- Check application configuration update
-- @treturn number(int) Latest version
function api:version()
	return pkg_api.conf_latest_version(self._sn, self._app, self._conf)
end

---
-- Get application configuration/template data by version
--
function api:data(version)
	local version = version
	if type(version) == 'number' then
		version = string.format("%d", version)
	end

	local data = self:_try_read_local_data(version)
	if data then
		return data, version
	end

	local data, err = pkg_api.conf_download(self._sn, self._app, self._conf, version)
	if data then
		self:_save_local_data(data, version)
	end
	return data, err
end

--- Fetch and return file path
function api:fetch(version)
	local data, version = self:data(version)
	if not data then
		return nil, version
	end
	return self:_local_filename(version)
end

function api:_local_filename(version)
	return self._dir.."/"..self._conf.."_"..version.."."..self._ext
end

function api:_try_read_local_data(version)
	local f, err = io.open(self:_local_filename(version), "r")
	if f then
		local data = f:read("*a")
		f:close()
		return data
	end
	return nil, err
end

function api:_save_local_data(data, version)
	local f, err = io.open(self:_local_filename(version), "w+")
	if f then
		f:write(data)
		f:close()
	end
	return nil, err
end

return api
