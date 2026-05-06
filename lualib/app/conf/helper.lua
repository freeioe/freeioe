---
-- 配置辅助模块
--
-- 本模块提供配置加载和模板管理的辅助功能
-- 支持从云端下载设备模板和配置
---

local class = require 'middleclass'
local skynet = require 'skynet'
local cjson = require 'cjson.safe'
local lfs = require 'lfs'

---
-- 配置辅助类
--
-- 处理应用配置、模板下载和设备管理
---
local helper = class("FREEIOE_APP_CONF_API_HELPER")

---
-- 初始化配置辅助对象
-- @param sys_api 系统API对象
-- @param conf 配置名称或配置表
-- @param templates_ext 模板文件扩展名（默认为"csv"）
-- @param templates_dir 模板保存目录（默认为"tpl"）
-- @param templates_node 配置中的模板节点名（默认为"tpls"）
-- @param devices_node 配置中的设备节点名（默认为"devs"）
function helper:initialize(sys_api, conf, templates_ext, templates_dir, templates_node, devices_node)
	assert(sys_api and conf)
	self._sys = sys_api
	self._log = sys_api:logger()
	self._conf = conf
	self._templates_ext = templates_ext or "csv"
	self._templates_dir = templates_dir or "tpl"
	self._templates_node = templates_node or "tpls"
	self._devices_node = devices_node or "devs"

	self._templates = {}
	self._devices = {}

	if not lfs.attributes(self._templates_dir, "mode") then
		lfs.mkdir(self._templates_dir)
	end
end

---
-- 从云端加载配置
-- @return 配置表
function helper:_load_conf()
	local conf_name, version = string.match(self._conf, "([^%.]+).(%d+)")
	conf_name = conf_name or self._conf
	version = math.tointeger(version)

	local api = self._sys:conf_api(conf_name, "cnf", self._templates_dir)

	--- 获取最新版本
	if not version then
		local ver, err = api:version()
		if not ver then
			self._log:warning("Get cloud configuration version failed", err)
			return {}
		end
		version = ver
	end

	--- 现在获取配置！
	self._log:notice("Loading cloud configuration", conf_name, version)

	local config, err = api:data(version)
	if not config then
		self._log:warning("Cloud configuration loading failed", err)
		return {}
	end
	-- 解码为JSON
	local conf, err = cjson.decode(config)
	if not conf then
		self._log:error("Cloud configuration decode error: "..err)
		return {}
	end
	return conf
end

---
-- 实际执行模板和设备获取
function helper:_real_fetch()
	if type(self._conf) == 'string' then
		self._conf = self:_load_conf()
	end

	local templates = self._conf[self._templates_node] or {}
	local devices = self._conf[self._devices_node] or {}

	--[[
	local inspect = require 'inspect'
	print(inspect(devices))
	]]--

	if #templates == 0 then
		self._log:warning('Cannot detect template list from configuration, by node name', self._templates_node)
		for _, dev in ipairs(devices) do
			self._devices[dev.name] = dev
		end
		return
	end

	while true do
		local not_finished = false
		for _, tpl in ipairs(templates) do
			if not self._templates[tpl.name] then
				local r, version = self:_download_tpl(tpl)
				if r and version == tonumber(tpl.ver) then
					self._log:info('download template finished. template:', tpl.id, tpl.ver)
					self._templates[tpl.name] = {
						id = tpl.id,
						name = tpl.name,
						ver = tpl.ver,
						data = r
					}
				else
					not_finished = true
					self._log:warning('Cannot fetch template', version)
				end
			end
		end
		for _, dev in ipairs(devices) do
			if not self._devices[dev.name] then
				if self._templates[dev.tpl] then
					self._log:info(string.format('Device [%s] with template [%s] is ready!!', dev.name, dev.tpl))
					self._devices[dev.name] = dev
				else
					self._log:warning(string.format('Cannot create device [%s] as template [%s] is not ready', dev.name, dev.tpl))
				end
			end
		end
		if not_finished then
			skynet.sleep(500)
		else
			break
		end
	end
end

---
-- 获取模板和设备
-- @param async 是否异步获取
function helper:fetch(async)
	if not async then
		return self:_real_fetch()
	else
		skynet.fork(function()
			self:_real_fetch()
		end)
	end
end

---
-- 获取配置
-- @return 配置表
function helper:config()
	return self._conf
end

---
-- 获取模板列表
-- @return 模板表
function helper:templates()
	local templates = {}
	for _, v in ipairs(self._conf[self._templates_node] or {}) do
		local tpl = self.templates[v.name]
		if tpl then
			table.insert(templates, tpl)
		end
	end
	return templates
end

---
-- 获取设备列表
-- @return 设备表
function helper:devices()
	local devices = {}
	for _, v in ipairs(self._conf[self._devices_node] or {}) do
		local dev = self._devices[v.name]
		if dev then
			table.insert(devices, dev)
		end
	end
	return devices
end

---
-- 下载模板文件
-- @param tpl 模板信息
-- @return 成功状态、版本号
function helper:_download_tpl(tpl)
	self._log:debug("conf_helper download template", tpl.id, tpl.name, tpl.ver)
	local api = self._sys:conf_api(tpl.id, self._templates_ext, self._templates_dir)
	local data, version = api:data(tpl.ver)
	if not data then
		return nil, version
	end
	local path = self._sys:app_dir()..self._templates_dir.."/"..tpl.name.."."..self._templates_ext
	local f, err = io.open(path, "w+")
	if not f then
		return nil, err
	end
	f:write(data)
	f:close()
	return true, tonumber(version)
end

return helper
