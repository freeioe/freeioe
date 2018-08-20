local datacenter = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local httpdown = require 'httpdown'
local log = require 'utils.log'
local class = require 'middleclass'

local api = class("APP_CONF_CENTER_API")

local api_header = {
	Accpet = "application/json"
}

--- Constructor
-- @tparam string app Application ID
-- @tparam string conf Application configuration Name or ID
-- @tparam string ext Local saving file extension. e.g. csv conf xml. default csv
-- @tparam string dir Application template file saving directory. full path.
function api:initialize(app, conf, ext, dir)
	-- Service host (ip or domain)
	self._host = datacenter.wait("CNF_HOST_URL")
	self._app = app
	self._conf = conf
	self._ext = ext or 'csv'
	self._dir = dir or 'tpl'
end

---
-- Check application configuration update
-- @treturn number(int) Latest version
function api:version()
	local url = '/conf_center/app_conf_version'
	local query = { sn = self._sn, app = self._app, conf = self._conf }
	local status, header, body = httpdown.get(self._host, url, api_header, query)
	log.info('conf_api.version', self._host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg, err = cjson.decode(body)
		if not msg.message then
			return nil, "No version found!"
		end
		return msg.message.version
	else
		return nil, body
	end
end

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
	log.info('conf_api.data', self._host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		if not msg.message then
			return nil, "Version not valided!"
		end
		self:_save_local_data(msg.message.data, msg.message.version)
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

return _M
