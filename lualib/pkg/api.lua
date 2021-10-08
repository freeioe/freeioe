local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local httpdown = require 'http.download'
local restful = require 'http.restful'
local sysinfo = require 'utils.sysinfo'
local helper = require 'utils.helper'
local log = require 'utils.logger'.new()
local ioe = require 'ioe'
local pkg = require 'pkg'

local _M = {}

_M.url_base = '/download'
_M.url_packages = '/download/packages'

_M.url_download = '/pkg/download'
_M.url_download_hash = '/pkg/download_hash'
_M.url_latest_version = '/pkg/latest_version' -- check version update
_M.url_check_version = '/pkg/check_version' -- check if it is beta
_M.url_user_access = '/pkg/user_access' -- User access device checking
_M.url_conf_download = '/pkg/conf/download'
_M.url_conf_latest_version = '/pkg/conf/latest_version'

function _M.http_post(url, data)
	local pkg_host = ioe.pkg_host_url()
	local api = restful:new(pkg_host)

	log.info('pkg.api.http_post', pkg_host..url)
	local status, body, header = api:post(url, nil, data)

	local ret = {}
	if status == 200 then
		local msg, err = cjson.decode(body)
		if msg.code ~= 0 or not msg.data then
			return nil, msg.msg or 'Response Message Error'
		end
		return msg.data
	else
		log.error(pkg_host..url, status, body)
		return nil, body
	end
end

function _M.latest_version(app, is_core)
	local beta = ioe.beta()

	local data = {
		app = app,
		device = ioe.id(),
		is_core = is_core,
		platform = sysinfo.platform(),
		beta = (beta == true and 1 or 0)
	}

	local data, err = _M.http_post(_M.url_latest_version, data)
	if data then
		return data -- { version: 111, beta: 0 }
	end
	return nil, 'Pull latest version failed, error: '..err
end

function _M.check_version(app, version, is_core)
	local data = {
		app = app,
		device = ioe.id(),
		is_core = is_core,
		platform = sysinfo.platform(),
		version = tostring(version)
	}

	local data, err = _M.http_post(_M.url_check_version, data)

	if data then
		return data --- { version: 111, beta: 0 }
	end
	return nil, 'Check version failed, error: '..err
end

function _M.user_access(auth_code)
	local headers = {
		Accpet = "application/json",
		['user-token'] = auth_code
	}

	local data = {
		device = ioe.id(),
		token = auth_code
	}

	return _M.http_post(_M.url_user_access, data)
end

--- Is Core is used by store v2
-- is_extension is used by store v1
function _M.create_download_func(app, version, ext, is_extension, token, is_core)
	--- PKG Version two
	if ioe.pkg_ver() > 1 then
		return _M.create_download_func_v2(app, version, ext, token, is_core)
	end

	--- All lua5.3 extension stop on version 43
	if is_extension and _VERSION == 'Lua 5.3' then
		version = 43
	end

	if version == 'latest' and ioe.beta() then
		version = 'latest.beta'
	end

	--- previously we using APP####### as appname
	local url_base = _M.url_packages
	if string.match(app, '^APP(%d+)$') then
		url_base = _M.url_base
	end

	return function(success_callback)
		local path = pkg.generate_tmp_path(app, version, ext)
		local file, err = io.open(path, "w+")
		if not file then
			return nil, err
		end

		local pkg_host = ioe.pkg_host_url()

		local url = url_base.."/"..app.."/"..version..ext
		if is_extension then
			local plat = sysinfo.platform()
			url = _M.url_packages.."/bin/"..plat.."/"..app.."/"..version..ext
		end

		log.notice('Start download package '..app..' from: '..pkg_host..url)
		local status, header, body = httpdown.get(pkg_host, url)
		if not status then
			return nil, "Download package "..app.." failed. Reason:"..tostring(header)
		end
		if status < 200 or status > 400 then
			return nil, "Download package failed, status code "..status
		end
		file:write(body)
		file:close()

		local md5_url = url..'.md5'
		local status, header, body = httpdown.get(pkg_host, md5_url)
		if status and status == 200 then
			local sum, err = helper.md5sum(path)
			if not sum then
				return nil, "Cannot caculate md5, error:\t"..err
			end
			log.notice("Downloaded file md5 sum", sum)
			local md5, cf = body:match('^(%w+)[^%g]+(.+)$')
			if sum ~= md5 then
				return nil, "Check md5 sum failed, expected:\t"..md5.."\t Got:\t"..sum
			end
		end
		return success_callback(path)
	end
end

function _M.create_download_func_v2(app, version, ext, token, is_core)
	--- Validate version
	if version == 'latest' or version == 'latest.beta' then
		version = ioe.beta() and 'latest.beta' or 'latest'
	end

	return function(success_callback)
		local path = pkg.generate_tmp_path(app, version, ext)
		local file, err = io.open(path, "w+")
		if not file then
			return nil, err
		end

		local pkg_host = ioe.pkg_host_url()

		local url = _M.url_download
		local hash_url = _M.url_download_hash
		local data = {
			device = ioe.id(),
			platform = sysinfo.platform(),
			token = token,
			app = app,
			version = version,
			is_core = is_core
		}

		log.notice('Start download package '..app..' from: '..pkg_host..url)
		local status, header, body = httpdown.get(pkg_host, url, {}, data)
		if not status then
			return nil, "Download package "..app.." failed. Reason:"..tostring(header)
		end

		if status < 200 or status > 400 then
			return nil, "Download package failed, status code "..status
		end
		file:write(body)
		file:close()

		data.hash = 'md5'
		local data, err = _M.http_post(hash_url, data)
		if not data then
			return nil, err
		end

		if data and data.hash and string.len(data.hash) > 0 then
			local sum, err = helper.md5sum(path)
			if not sum then
				return nil, "Cannot caculate md5, error:\t"..err
			end
			log.notice("Downloaded file md5 sum", sum)
			if sum ~= data.hash then
				return nil, "Check md5 sum failed, expected:\t"..data.hash.."\t Got:\t"..sum
			end
		end
		return success_callback(path)
	end
end

function _M.conf_latest_version(app_sn, app, conf)
	if ioe.pkg_ver() >= 2 then
		return _M.conf_latest_version_v2(app, conf)
	end

	local pkg_host = ioe.pkg_host_url()
	local api_header = {
		Accpet = "application/json"
	}
	local url = '/conf_center/get_latest_version'
	local query = { sn = app_sn, app = app, conf = conf }
	local status, header, body = httpdown.get(pkg_host, url, api_header, query)
	log.debug('conf_api.version', pkg_host..url, status, body or header)
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

function _M.conf_latest_version_v2(app, conf)
	local data = {
		app = app,
		device = ioe.id(),
		platform = sysinfo.platform(),
		conf = conf,
	}

	local data, err = _M.http_post(_M.url_conf_latest_version, data)
	if data then
		--return data -- { version: 111 }
		return tonumber(data.version) or 0
	end
	return nil, 'Pull latest version failed, error: '..err
end

function _M.conf_download(app_sn, app, conf, version, token)
	if ioe.pkg_ver() >= 2 then
		return _M.conf_download_v2(app, conf, version, token)
	end

	local pkg_host = ioe.pkg_host_url()
	local api_header = {
		Accpet = "application/json"
	}
	local url = '/conf_center/app_conf_data'
	local query = { sn = app_sn, app = app, conf = conf, version = version }
	local status, header, body = httpdown.get(pkg_host, url, api_header, query)
	log.debug('conf_api.data', pkg_host..url, status, body or header)
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
		return msg.message.data, msg.message.version
	else
		return nil, body
	end
end

function _M.conf_download_v2(app, conf, version, token)
	local data = {
		app = app,
		device = ioe.id(),
		token = token,
		platform = sysinfo.platform(),
		conf = conf,
		version = version
	}

	local data, err = _M.http_post(_M.url_conf_download, data)
	if data then
		--data -- { data: "xxxxxx" }
		return data.data, tonumber(data.version)
	end
	return nil, 'Pull conf data failed, error: '..err
end

return _M
