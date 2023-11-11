local lfs = require 'lfs'
local sha1 = require 'hashings.sha1'
local hmac = require 'hashings.hmac'
local ioe = require 'ioe'

local _M = {}

--- trim instance name
function _M.trim_inst(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("", string.byte(c))
	end))
end

function _M.valid_inst(s)
	return s and #s > 0 and s == _M.trim_inst(s)
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
	return lfs.currentdir().."/ioe/ext/"..inst_name
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
	local app_name_escape = string.gsub(app_name, '/', '__')
	return "/tmp/"..app_name_escape.."_"..version..os.time()..ext
end

function _M.gen_token(id)
	local secret = ioe.cloud_secret()
	return hmac:new(sha1, secret, id):hexdigest() --- hash the id as token
end

return _M
