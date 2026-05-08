local lfs = require 'lfs'
local sha1 = require 'hashings.sha1'
local hmac = require 'hashings.hmac'
local ioe = require 'ioe'

local _M = {}

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
	-- 防止路径遍历攻击，验证不包含路径分隔符
	if inst_name:match('[/\\]') then
		return nil, "Invalid instance name: contains path separators"
	end
	return ioe.dir().."/apps/"..inst_name.."/"
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
	return ioe.dir(true).."/ext/"
end

function _M.get_ext_folder(inst_name)
	assert(string.len(inst_name or '') > 0, "Instance name cannot be empty")
	-- 防止路径遍历攻击，验证不包含路径分隔符
	if inst_name:match('[/\\]') then
		return nil, "Invalid instance name: contains path separators"
	end
	return ioe.dir(true).."/ext/"..inst_name
end

function _M.parse_version_string(version)
	if type(version) == 'number' then
		return tostring(math.floor(version)), false
	end
	if not version or version == '' then
		version = 'latest'
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

function _M.generate_tmp_path(app_name, version, ext)
	assert(app_name, "App name is nil")
	-- 转义所有路径分隔符和危险字符
	local app_name_escape = string.gsub(app_name, '[/\\:%.%c]', '__')
	-- 添加随机数以防止预测和竞态条件
	local random_suffix = string.format("%04x", math.random(0, 65535))
	return "/tmp/"..app_name_escape.."_"..version.."_"..os.time().."_"..random_suffix..ext
end

function _M.gen_token(id)
	local secret = ioe.cloud_secret()
	return hmac:new(sha1, secret, id):hexdigest() --- hash the id as token
end

return _M
