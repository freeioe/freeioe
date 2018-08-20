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
function api:initialize(app, conf)
	-- Service host (ip or domain)
	self._host = datacenter.wait("CNF_HOST_URL")
	self._app = app
	self._conf = conf
end

---
-- Check application configuration update
-- @treturn number(int) Latest version
function api:version()
	local url = '/conf_center/app_conf_version'
	local query = { app = self._app, conf = self._conf }
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
	local url = '/conf_center/app_conf_data'
	local query = { app = self._app, conf = self._conf, version = version }
	local status, header, body = httpdown.get(self._host, url, api_header, query)
	log.info('conf_api.data', self._host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		if not msg.message then
			return nil, "Version not valided!"
		end
		return msg.message.data, msg.message.version
	else
		return nil, body
	end
end

return _M
