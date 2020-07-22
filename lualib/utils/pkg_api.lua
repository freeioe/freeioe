local skynet = require 'skynet'
local datacenter = require 'skynet.datacenter'
local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local httpdown = require 'http.download'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'
local helper = require 'utils.helper'
local ioe = require 'ioe'

local _M = {}

_M.url_base = '/download'
_M.url_packages = '/download/packages'

local api_header = {
	Accpet="application/json"
}

--- trim instance name
function _M.trim_inst(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("", string.byte(c))
	end))
end

function _M.valid_inst(s)
	return s and #s > 0 and s == _M.trim_inst(s)
end

function _M.pkg_check_update(pkg_host, app, beta)
	local url = '/pkg/check_update'
	local query = { app = app }
	if beta then
		query.beta = 1
	end
	local status, header, body = httpdown.get(pkg_host, url, api_header, query)
	log.info('pkg_check_update', pkg_host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg, err = cjson.decode(body)
		if not msg.message then
			return nil, "No version found!"
		end
		return msg.message.version, msg.message.beta == 1
	else
		return nil, body
	end
end

function _M.pkg_enable_beta(pkg_host, sys_id)
	local url = '/pkg/enable_beta'
	local status, header, body = httpdown.get(pkg_host, url, api_header, {sn=sys_id})
	log.info('pkg_enable_beta', pkg_host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		local val = tonumber(msg.message or 0)
		return val == 1
	else
		return nil, body
	end
end

function _M.pkg_user_access(pkg_host, sys_id, auth_code)
	local url = '/pkg/user_access_device'
	local headers = {
		Accpet="application/json",
		AuthorizationCode=auth_code
	}
	local status, header, body = httpdown.get(pkg_host, url, headers, {sn=sys_id})
	log.info('pkg_user_access', pkg_host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		return msg.message == true
	else
		return nil, body
	end

end

function _M.pkg_check_version(pkg_host, app, version)
	local version = version
	if type(version) == 'number' then
		version = string.format("%d", version)
	end
	local url = '/pkg/check_version'
	local status, header, body = httpdown.get(pkg_host, url, api_header, {app=app, version=version})
	log.info('pkg_check_version', pkg_host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		if not msg.message then
			return nil, "Version not valided"
		end
		return msg.message
	else
		return nil, body
	end
end

function _M.pkg_latest_version(pkg_host, app, beta)
	local beta = beta and 1 or 0
	local url = '/pkg/get_latest_version'
	local status, header, body = httpdown.get(pkg_host, url, api_header, {app=app, beta=beta})
	log.info('pkg_check_version', pkg_host..url, status, body or header)
	local ret = {}
	if status == 200 then
		local msg = cjson.decode(body)
		if not msg.message then
			return nil, "Version not found!"
		end
		return msg.message
	else
		return nil, body
	end
end

function _M.get_app_version(inst_name)
	local dir = _M.get_app_folder(inst_name)
	local f, err = io.open(dir.."/version", "r")
	if not f then
		return nil, err
	end
	local v, err = f:read('l')
	f:close()
	if not v then
		return err
	end
	return tonumber(v)
end


function _M.get_app_folder(inst_name)
	assert(string.len(inst_name or '') > 0, "Instance name cannot be empty")
	return lfs.currentdir().."/ioe/apps/"..inst_name.."/"
	--return os.getenv("PWD").."/ioe/apps/"..inst_name
end

function _M.get_ext_version(inst_name)
	local dir = _M.get_ext_folder(inst_name)
	local f, err = io.open(dir.."/version", "r")
	if not f then
		return nil, err
	end
	local v, err = f:read('l')
	f:close()
	if not v then
		return err
	end
	return tonumber(v)
end

function _M.get_ext_root()
	return lfs.currentdir().."/ioe/ext/"
end

function _M.get_ext_folder(inst_name)
	assert(string.len(inst_name or '') > 0, "Instance name cannot be empty")
	return lfs.currentdir().."/ioe/ext/"..inst_name.."/"
end

function _M.parse_version_string(version)
	if type(version) == 'number' then
		return tostring(math.floor(version)), false
	end

	local editor = false
	local beta = false
	local version = version or 'latest'
	if string.len(version) > 5 and string.sub(version, 1, 5) == 'beta.' then
		version = string.sub(version, 6)
		beta = true
	end
	if string.len(version) > 7 and string.sub(version, -7) == '.editor' then
		version = string.sub(version, 1, -8)
		beta = true
		editor = true
	end
	return version, beta, editor
end

function _M.generate_tmp_path(inst_name, app_name, version, ext)
	local app_name_escape = string.gsub(app_name, '/', '__')
	return "/tmp/"..inst_name..'__'..app_name_escape.."_"..version..ext
end

function _M.create_download_func(inst_name, app_name, version, ext, is_extension)
	local inst_name = inst_name
	--local app_name = app_name:gsub('%.', '/')
	local app_name = app_name
	local version = version
	local ext = ext
	local is_extension = is_extension

	if version == 'latest' and ioe.beta() then
		version = 'latest.beta'
	end

	--- previously we using APP####### as appname
	local url_base = _M.url_packages
	if string.match(app_name, '^APP(%d+)$') then
		url_base = _M.url_base
	end

	return function(success_callback)
		--local app_name_escape = string.gsub(app_name, '/', '__')
		--local path = "/tmp/"..inst_name..'__'..app_name_escape.."_"..version..ext
		local path = _M.generate_tmp_path(inst_name, app_name, version, ext)
		local file, err = io.open(path, "w+")
		if not file then
			return nil, err
		end

		local pkg_host = ioe.pkg_host_url()

		local url = url_base.."/"..app_name.."/"..version..ext
		if is_extension then
			local plat = sysinfo.platform()
			url = _M.url_packages.."/bin/"..plat.."/"..app_name.."/"..version..ext
		end

		log.notice('Start download package '..app_name..' from: '..pkg_host..url)
		local status, header, body = httpdown.get(pkg_host, url)
		if not status then
			return nil, "Download package "..app_name.." failed. Reason:"..tostring(header)
		end
		if status < 200 or status > 400 then
			return nil, "Download package failed, status code "..status
		end
		file:write(body)
		file:close()

		local status, header, body = httpdown.get(pkg_host, url..".md5")
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

return _M
