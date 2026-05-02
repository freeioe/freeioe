---
-- Configuration API Module
--
-- This module provides access to application configuration and templates
-- from a central configuration server with local caching support.
--
---

local datacenter = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local httpdown = require 'http.download'
local class = require 'middleclass'
local pkg_api = require 'pkg.api'
local ioe = require 'ioe'
local lfs = require 'lfs'

---
-- Configuration API Class
--
-- Handles configuration and template retrieval with local caching
-- for improved performance and offline capability.
---
local api = class("FREEIOE_APP_CONF_CENTER_API")

---
-- HTTP headers for API requests
---
local api_header = {
	Accpet = "application/json"
}

---
-- Constructor
-- @param sys: system API object
-- @param app: application ID
-- @param conf: configuration ID
-- @param ext: local file extension (csv, conf, xml, etc.), default 'csv'
-- @param dir: template save directory (full path), default 'tpl'
---
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
-- @return: latest version number
---
function api:version()
	return pkg_api.conf_latest_version(self._sn, self._app, self._conf)
end

---
-- Get application configuration/template data by version
-- Tries local cache first, then downloads from remote
-- @param version: configuration version (nil for latest)
-- @return: data string, version or nil, error message
---
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

---
-- Fetch configuration and return local file path
-- @param version: configuration version (nil for latest)
-- @return: local file path or nil, error message
---
function api:fetch(version)
	local data, version = self:data(version)
	if not data then
		return nil, version
	end
	return self:_local_filename(version)
end

---
-- Generate local filename for cached configuration
-- @param version: configuration version
-- @return: local file path
---
function api:_local_filename(version)
	return self._dir.."/"..self._conf.."_"..version.."."..self._ext
end

---
-- Try to read locally cached configuration data
-- @param version: configuration version
-- @return: data string or nil, error message
---
function api:_try_read_local_data(version)
	local f, err = io.open(self:_local_filename(version), "r")
	if f then
		local data = f:read("*a")
		f:close()
		return data
	end
	return nil, err
end

---
-- Save configuration data to local cache
-- @param data: configuration data string
-- @param version: configuration version
-- @return: nil, error message on failure
---
function api:_save_local_data(data, version)
	local f, err = io.open(self:_local_filename(version), "w+")
	if f then
		f:write(data)
		f:close()
	end
	return nil, err
end

return api
