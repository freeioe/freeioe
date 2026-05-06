---
-- 配置初始化模块
--
-- 本模块处理应用配置文件的加载和默认值管理
--

local skynet = require 'skynet'
local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local class = require 'middleclass'

---
-- 配置类
--
-- 从JSON文件加载配置并提供默认值映射功能
---
local conf = class("FREEIOE_APP_CONF_INIT")

---
-- 实际加载默认值配置
-- @param filename 配置文件路径
-- @return 默认值表
local function load_defaults_real(filename)
	local f = assert(io.open(filename))
	local str = f:read('*a')
	local data = assert(cjson.decode(str))
	f:close()

	--- 解析JSON数据

	local default = {}
	for _, v in ipairs(data) do
		if v.default ~= nil then
			default[v.name] = v.default
		end
	end

	return default
end

---
-- 加载默认配置
-- @param filename 配置文件路径
-- @return 默认值表
function conf:_load_defaults(filename)
	if 'file' ~= lfs.attributes(filename, 'mode') then
		return {}
	end

	local r, data = pcall(load_defaults_real, filename)
	if not r then
		self._log:error('Load app config file '..filename..' failed!', data)
		return {}
	else
		self._log:info('Loaded app config template file'..filename..'!!')
	end
	return data or {}
end

---
-- 初始化配置对象
-- @param sys 系统API对象
-- @param conf_json 配置文件名（默认为'conf.json'）
function conf:initialize(sys, conf_json)
	self._sys = sys
	self._log = sys:logger()
	self._conf_json = conf_json or 'conf.json'

	local filename = self._sys:app_dir()..'/'..self._conf_json
	self._default = self:_load_defaults(filename)

end

---
-- 将配置表映射到默认值
-- @param conf_t 配置表
-- @return 带有默认值访问的配置表
function conf:map(conf_t)
	return setmetatable(conf_t or {}, {__index = self._default})
end

---
-- 调用映射函数的快捷方式
-- @param conf_t 配置表
-- @return 带有默认值访问的配置表
function conf:__call(conf_t)
	return self:map(conf_t)
end

return conf
