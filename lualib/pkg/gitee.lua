local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local httpdown = require 'http.download'
local sysinfo = require 'utils.sysinfo'
local helper = require 'utils.helper'
local log = require 'utils.logger'.new()
local ioe = require 'ioe'
local pkg = require 'pkg'

local _M = {}

-- first param is full repo name [ ownwer/repo ]
-- second param is branch/tag name
_M.url_fmt = '/%s/repository/archive/%s.zip'
--_M.url_fmt = '/%s/archive/refs/tags/%s.zip'
_M.url_sub_fmt = '/%s/raw/%s/%s'
_M.host = 'https://gitee.com'
_M.req_header = {
	['User-Agent'] = 'FreeIOE/1.0.0',
	['Accept'] = '*/*',
	['Accept-Encoding'] = 'identity'
}

local function test_exists(repo_path, branch_tag, path)
	local url = string.format(_M.url_sub_fmt, repo_path, branch_tag, path)
	local status, header, body = httpdown.get(_M.host, url, {})
	if not status then
		return false
	end

	if status < 200 or status > 400 then
		return false
	end
	return true
end

local patts = {
	['<PLAT>'] = sysinfo.platform(),
	['<ARCH>'] = sysinfo.cpu_arch(),
	['<GOARCH>'] = sysinfo.go_arch(),
}
local function replace_patt(path)
	for k, v in pairs(patts) do
		path = string.gsub(path, k, v)
	end
	return path
end

function _M.gen_inst_name(ext)
	local repo = replace_patt(ext.repo)
	local version = replace_patt(ext.version)
	if not ext.path then
		return 'gitee__'..repo:gsub('/', '__').."."..version
	else
		return 'gitee__'..repo:gsub('/', '__').."."..version.."__"..ext.name
	end
end

function move_all_files(src_dir, dst_dir)
    for file in lfs.dir(src_dir) do
        if file ~= "." and file ~= ".." then
            local src_path = src_dir .. "/" .. file
            local dst_path = dst_dir .. "/" .. file
            os.rename(src_path, dst_path)
        end
    end
end

function _M.post_install(inst, ext, folder)
	local ext_repo = replace_patt(ext.repo)
	local ext_version = replace_patt(ext.version)
	local owner, repo = string.match(ext_repo, '([^/]+)/(.+)')
	local sub_folder = folder..'/'..repo..'-'..ext_version
	log.notice('Post install sub folder:', sub_folder)
	if lfs.attributes(sub_folder, 'mode') == 'directory' then
		move_all_files(sub_folder, folder)
		-- 使用 shell 转义来避免命令注入
		local function shell_escape(s)
			return '"' .. string.gsub(s, '"', '\\"') .. '"'
		end
		os.execute("rmdir "..shell_escape(sub_folder))
	end
end

function _M.create_download_func(ext)
	local repo_path = ext.repo
	local branch_tag = ext.version
	local file_path = ext.path
	if not string.match(repo_path, "^([^/]+)/([^/]+)$") then
		return nil, "repo_path must be <owner/repo>"
	end
	repo_path = replace_patt(repo_path)

	branch_tag = tostring(branch_tag) or 'master' -- to be main???
	branch_tag = replace_patt(branch_tag)

	if not file_path then
		return function(success_callback)
			local path = pkg.generate_tmp_path(repo_path, branch_tag, ".zip")
			local file, err = io.open(path, "w+")
			if not file then
				return nil, err
			end

			local url = string.format(_M.url_fmt, repo_path, branch_tag)

			log.notice(string.format('Start download gitee repo:%s - %s from %s%s',
					repo_path, branch_tag, _M.host, url))
			local status, header, body = httpdown.get(_M.host, url, {
				['User-Agent'] = 'Wget/1.25.0',
				['Accept'] = '*/*',
				['Accept-Encoding'] = 'identity'
			})
			if not status then
				return nil, "Download repo:"..repo_path.." failed. Reason:"..tostring(header)
			end

			if status < 200 or status > 400 then
				return nil, "Download repo failed, status code "..status
			end
			file:write(body)
			file:close()

			return success_callback(path)
		end
	else
		return function(success_callback)
			file_path = replace_patt(file_path)
			file_path = string.gsub(file_path, '/', '__')

			local path = pkg.generate_tmp_path(repo_path, branch_tag, "."..file_path)
			local file, err = io.open(path, "w+")
			if not file then
				return nil, err
			end

			local url = string.format(_M.url_sub_fmt, repo_path, branch_tag, path)
			local status, header, body = httpdown.get(_M.host, url, {})
			if not status then
				return nil, "Download repo:"..repo_path.." failed. Reason:"..tostring(header)
			end

			if status < 200 or status > 400 then
				return nil, "Download repo failed, status code "..status
			end
			file:write(body)
			file:close()

			return success_callback(path)
		end
	end
end

return _M
