---
-- 调试工具模块
--
-- 本模块为应用提供调试工具，
-- 包括用于诊断目的的缓冲区打包功能。
---

local skynet = require 'skynet'
local snax = require 'skynet.snax'
local lfs = require 'lfs'
local cjson = require 'cjson.safe'
local sysinfo = require 'utils.sysinfo'
local class = require 'middleclass'
local app_logger = require 'app.logger'

---
-- 调试工具类
--
-- 提供收集和保存应用调试信息的方法，
-- 包括通信日志和系统日志。
---
local debug = class("APP_LIB_DEBUG")

---
-- 初始化调试工具实例
-- @param app_name: 应用名称
-- @param logger: 可选的日志记录器实例（如为nil则创建默认实例）
---
function debug:initialize(app_name, logger)
	self._app_name = app_name
	self._logger = logger or app_logger:new(app_name)
end

---
-- 将所有应用通信和日志数据打包到文件中
-- 从缓冲区服务查询应用特定数据并保存为JSON文件
-- @return: 成功返回文件名，失败返回nil和错误信息
---
function debug:pack_all()
	local buffer, err = snax.queryservice('buffer')
	if not buffer then
		return nil, err
	end
	local comms = buffer.req.get_comm(self._app_name) or {}
	local logs = buffer.req.get_log(self._app_name) or {}

	local dir = sysinfo.data_dir()..'/freeioe_buffer_pack'
	lfs.mkdir(dir)
	local fn = string.format('%s/%s.%d.pack', dir, self._app_name, os.time())
	local f, err = io.open(fn, 'w+')
	if not f then
		return nil, err
	end

	local data, err = cjson.encode({
		comm = comms,
		log = logs
	})
	if not data then
		return nil, err
	end

	f:write(data)
	f:close()

	return fn
end

return debug
