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
_M.url_latest_version = '/pkg/latest_version' -- check version update
_M.url_check_version = '/pkg/check_version' -- check if it is beta
_M.url_user_access = '/pkg/user_access' -- User access device checking

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

	local query = {
		app = app,
		device = ioe.id(),
		is_core = is_core,
		platform = sysinfo.platform(),
		beta = (beta == true and 1 or 0)
	}

	local data, err = _M.http_post(_M.url_latest_version, query)
	if data then
		return data -- {version: 111, beta: 0}
	end
	return nil, err
end

function _M.check_version(app, version, is_core)
	local version = tonumber(version) or 0

	local data = {
		app = app,
		device = ioe.id(),
		is_core = is_core,
		platform = sysinfo.platform(),
		version = version
	}

	local data, err = _M.http_post(_M.url_check_version, data)

	if data then
		return data.beta --- true or false
	end
	return nil, err
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

local function get_core_name(name)
	assert(name, 'Core name is required!')
	local platform = sysinfo.platform()
	if platform then
		--name = platform.."_"..name
		--- FreeIOE not takes the os version before. so using openwrt/arm_cortex-a9_neon_skynet as download core name
		---		now it switched to bin/openwrt/17.01/arm_cortex-a9_neon/skynet
		name = string.format("bin/%s/%s", platform, name)
	end
	return name
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

	if is_extension and app ~= 'freeioe' then
		app = get_core_name(app)
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
		local status, header, body = httpdown.get(pkg_host, url, {}, query)
		if not status then
			return nil, "Download package "..app.." failed. Reason:"..tostring(header)
		end
		if status < 200 or status > 400 then
			return nil, "Download package failed, status code "..status
		end
		file:write(body)
		file:close()

		local md5_url = url..'.md5'
		local status, header, body = httpdown.get(pkg_host, md5_url, {}, query)
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
	else
		version = tonumber(version) or 0
	end

	return function(success_callback)
		local path = pkg.generate_tmp_path(app, version, ext)
		local file, err = io.open(path, "w+")
		if not file then
			return nil, err
		end

		local pkg_host = ioe.pkg_host_url()

		local url = _M.url_download
		local md5_url = _M._url_download_md5
		local query = {
			device = ioe.id(),
			platform = sysinfo.platform(),
			token = token,
			app = app,
			version = version,
			is_core = is_core
		}

		log.notice('Start download package '..app..' from: '..pkg_host..url)
		local status, header, body = httpdown.get(pkg_host, url, {}, query)
		if not status then
			return nil, "Download package "..app.." failed. Reason:"..tostring(header)
		end

		if status < 200 or status > 400 then
			return nil, "Download package failed, status code "..status
		end
		file:write(body)
		file:close()

		local data, err = _M.http_post(md5_url, query)
		if not data then
			return nil, err
		end

		if data and data.md5 then
			local sum, err = helper.md5sum(path)
			if not sum then
				return nil, "Cannot caculate md5, error:\t"..err
			end
			log.notice("Downloaded file md5 sum", sum)
			if sum ~= data.md5 then
				return nil, "Check md5 sum failed, expected:\t"..data.md5.."\t Got:\t"..sum
			end
		end
		return success_callback(path)
	end
end

return _M
