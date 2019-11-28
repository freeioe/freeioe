local datacenter = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local httpdown = require 'http.download'
local log = require 'utils.log'
local class = require 'middleclass'
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
function api:initialize(app, conf, ext, dir)
	-- Service host (ip or domain)
	self._host = ioe.cnf_host_url() --datacenter.wait("CLOUD", "CNF_HOST_URL")
	self._app = app
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
	local url = '/conf_center/get_latest_version'
	local query = { sn = self._sn, app = self._app, conf = self._conf }
	local status, header, body = httpdown.get(self._host, url, api_header, query)
	log.debug('conf_api.version', self._host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg, err = cjson.decode(body)
		if not msg then
			return nil, err
		end
		if not msg.message then
			return nil, "No version found!"
		end
		if type(msg.message) == 'table' then
			return math.tointeger(msg.message.version or msg.message.Version)
		else
			return math.tointeger(msg.message)
		end
	else
		return nil, body
	end
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
	
	local url = '/conf_center/app_conf_data'
	local query = { sn = self._sn, app = self._app, conf = self._conf, version = version }
	local status, header, body = httpdown.get(self._host, url, api_header, query)
	log.debug('conf_api.data', self._host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		if not msg then
			return nil, err
		end
		if not msg.message then
			return nil, "Version not valided!"
		end
		if math.tointeger(msg.message.version) == -1 then
			return nil, "Cloud configuration not found in sever!"
		end
		if math.tointeger(msg.message.version) ~= tonumber(version) then
			return nil, "Version is different"
		end
		self:_save_local_data(msg.message.data, version)
		return msg.message.data, msg.message.version
	else
		return nil, body
	end
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
