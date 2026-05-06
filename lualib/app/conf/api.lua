---
-- 配置API模块
--
-- 本模块提供从中央配置服务器访问应用配置和模板的功能，
-- 支持本地缓存以提高性能和离线能力。
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
-- 配置API类
--
-- 处理配置和模板检索，支持本地缓存
-- 以提高性能和离线能力。
---
local api = class("FREEIOE_APP_CONF_CENTER_API")

---
-- API请求的HTTP头
---
local api_header = {
	Accpet = "application/json"
}

---
-- 构造函数
-- @param sys: 系统API对象
-- @param app: 应用ID
-- @param conf: 配置ID
-- @param ext: 本地文件扩展名（csv、conf、xml等），默认为'csv'
-- @param dir: 模板保存目录（完整路径），默认为'tpl'
---
function api:initialize(sys, app, conf, ext, dir)
	-- 服务主机（IP或域名）
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
-- 检查应用配置更新
-- @return: 最新版本号
---
function api:version()
	return pkg_api.conf_latest_version(self._sn, self._app, self._conf)
end

---
-- 按版本获取应用配置/模板数据
-- 首先尝试本地缓存，然后从远程下载
-- @param version: 配置版本（nil表示最新版本）
-- @return: 数据字符串、版本或nil、错误信息
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
-- 获取配置并返回本地文件路径
-- @param version: 配置版本（nil表示最新版本）
-- @return: 本地文件路径或nil、错误信息
---
function api:fetch(version)
	local data, version = self:data(version)
	if not data then
		return nil, version
	end
	return self:_local_filename(version)
end

---
-- 为缓存配置生成本地文件名
-- @param version: 配置版本
-- @return: 本地文件路径
---
function api:_local_filename(version)
	return self._dir.."/"..self._conf.."_"..version.."."..self._ext
end

---
-- 尝试读取本地缓存的配置数据
-- @param version: 配置版本
-- @return: 数据字符串或nil、错误信息
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
-- 将配置数据保存到本地缓存
-- @param data: 配置数据字符串
-- @param version: 配置版本
-- @return: nil，失败时返回错误信息
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
