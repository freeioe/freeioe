local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local coroutine = require 'skynet.coroutine'
local class = require 'middleclass'
local ioe = require 'ioe'
local api = require 'app.api'
local logger = require 'app.logger'
local conf_api = require 'app.conf.api'
local utils = require 'app.utils'
local debug_utils = require 'app.debug'
local cancelable_timeout = require 'cancelable_timeout'

local sys = class("APP_MGR_SYS")
sys.API_VER = 17 -- 2026.04.22 :: Improved app depends download
sys.API_MIN_VER = 1

---
-- 按级别写入日志
-- @tparam level string 日志级别字符串（error、info、notice、debug、trace）
function sys:log(level, ...)
	return self._logger:log(level, ...)
end

---
-- 获取日志记录器接口对象
-- @treturn logger object 日志记录器对象
function sys:logger()
	return self._logger
end

---
-- 转储通信流数据
-- @tparam sn string 设备序列号
-- @tparam dir string 方向描述
-- @treturn nil
function sys:dump_comm(sn, dir, ...)
	local sn = sn or self:app_sn()
	return self._data_api:_dump_comm(sn, dir, ...)
end

---
-- 触发应用事件
-- @tparam sn string 设备序列号
-- @tparam level number 事件级别（参考app.event模块的LEVELS）
-- @tparam type_ number 事件类型（参考app.event模块的EVENTS）
-- @tparam info string 事件信息
-- @tparam data table 事件数据表对象
-- @tparam timestamp number 事件发生时间戳（或iot.time()）
function sys:fire_event(sn, level, type_, info, data, timestamp)
	return self._data_api:_fire_event(sn or self:app_sn(), level, type_, info, data or {}, timestamp or ioe.time())
end

---
-- 派生新协程来运行函数
-- @tparam func function 执行函数
-- @tparam ... args 参数
function sys:fork(func, ...)
	skynet.fork(func, ...)
end

---
-- 设置超时函数执行
-- @tparam ms number 时间（毫秒）
-- @tparam func function 执行函数
function sys:timeout(ms, func)
	return skynet.timeout(ms / 10, func)
end

---
-- 创建可取消的超时函数执行
-- @tparam ms number 时间（毫秒）
-- @tparam func function 执行函数
-- @treturn function 取消函数持有者
function sys:cancelable_timeout(ms, func)
	local cancel = cancelable_timeout(ms / 10, func)
	return cancel
end

---
-- 退出当前应用进程
--   这不会保存数据
function sys:exit()
	skynet.exit()
end

---
-- 在五秒后中止FreeIOE应用
function sys:abort()
	self._logger:warning("FreeIOE will be closed after 5 seconds!")
	ioe.abort(5000)
end

---
-- 获取FreeIOE运行时间（毫秒）
-- @treturn number 毫秒数
function sys:now()
	return skynet.now() * 10
end

---
-- 尝试修复FreeIOE时间问题（由NTP引起）
function sys:fix_time()
	if skynet.fix_time then
		local r = skynet.fix_time()
		--- 之前的fix_time不返回任何值，所以r将为nil
		if r or r == nil then
			return
		end
	end

	self._logger:warning("Reboot FreeIOE to fix time diff issue!")
	self:abort()
end

---
-- 获取当前时间秒数（UTC当前时间）
-- @treturn number 参考ioe.time()
function sys:time()
	return ioe.time()
end

---
-- 获取FreeIOE启动时间（UTC，秒）
-- @treturn number 参考ioe.starttime()
function sys:start_time()
	return ioe.starttime()
end

---
-- 让当前协程让出执行权
function sys:yield()
	return skynet.yield()
end

---
-- 休眠当前协程，让其他协程运行
-- @tparam ms number 休眠时间（毫秒）
-- @tparam token 可用于中止休眠的令牌
function sys:sleep(ms, token)
	local ts = math.floor(ms / 10)
	return skynet.sleep(ts, token)
end

---
-- 获取数据访问API
-- @treturn object 参考app.api
function sys:data_api()
	return self._data_api
end

---
-- 获取调试API（未实现）
function sys:debug_api()
	if self._debug_api then
		self._debug_api = debug_utils:new(app_name, self._logger)
	end
	return  self._debug_api
end

---
-- 获取当前协程对象
function sys:self_co()
	return coroutine.running()
end

---
-- 等待被令牌唤醒
-- @tparam any 用于唤醒此等待的令牌
function sys:wait(token)
	return skynet.wait(token)
end

---
-- 唤醒指定令牌的协程
-- @tparam any 休眠/等待协程令牌
function sys:wakeup(token)
	return skynet.wakeup(token)
end

---
-- 获取当前应用目录
function sys:app_dir()
	return utils.app_path(self._app_name)
end

---
-- 获取应用序列号
function sys:app_sn()
	local app_sn = self._app_sn
	if app_sn then
		return app_sn
	end

	app = dc.get("APPS", self._app_name)
	if app then
		app_sn = app.sn
	end
	if not app_sn then
		local cloud = snax.queryservice('cloud')
		app_sn = cloud.req.gen_sn(self._app_name)
	end
	self._app_sn = app_sn

	return self._app_sn
end

---
-- 获取应用配置
function sys:get_conf(default_config)
	app = dc.get("APPS", self._app_name)
	local conf = {}
	if app and app.conf then
		conf = app.conf
	end
	if not default_config then
		return conf
	end
	return setmetatable(conf, {__index = default_config})
end

---
-- 设置应用配置
function sys:set_conf(config)
	app = dc.get("APPS", self._app_name)
	if app then
		app.conf = config
		dc.set("APPS", self._app_name, app)
		return  true
	end
end

--- 获取云配置API
-- @tparam string conf_name 云应用配置ID
-- @tparam string ext 本地保存文件扩展名。例如csv conf xml。默认为csv
-- @tparam string dir 应用模板文件保存目录。<当前路径>/tpl
-- @treturn conf_api
function sys:conf_api(conf_name, ext, dir)
	local dir = self:app_dir()..(dir or 'tpl')
	app = dc.get("APPS", self._app_name)
	return conf_api:new(self, app.name, conf_name, ext, dir)
end

---
-- 获取应用名称和版本
-- @treturn string 应用实例名称
-- @treturn number 应用版本号
function sys:version()
	app = dc.get("APPS", self._app_name)
	return app.name, app.version
end

---
-- 生成设备序列号
-- @tparam string device 用于生成序列号的设备名称
function sys:gen_sn(dev_name)
	local cloud = snax.queryservice('cloud')
	return cloud.req.gen_sn(self._app_name.."."..dev_name)
end

---
-- 获取系统ID
function sys:id()
	return ioe.id()
end

---
-- 获取硬件ID
function sys:hw_id()
	return ioe.hw_id()
end

---
-- 向应用自身发起请求，如果on_post不存在将调用app.response或on_req_<msg>
function sys:req(msg, ...)
	assert(self._wrap_snax)
	return self._wrap_snax.req.app_req(msg, ...)
end

---
-- 向应用自身发送消息，如果on_post不存在将调用app.accept或on_post_<msg>
function sys:post(msg, ...)
	assert(self._wrap_snax)
	return self._wrap_snax.post.app_post(msg, ...)
end

--- POST到云端
local CLOUD_WHITE_LIST_POST = {
	'enable_data_one_short',
	'enable_event',
	'download_cfg',
	'upload_cfg',
	'fire_data_snapshot',
	'batch_script',
}
---
-- 调用云端post操作
-- @tparam func string 操作名称
-- @tparam ... args 操作参数
function sys:cloud_post(func, ...)
	local found = false
	for _, v in ipairs(CLOUD_WHITE_LIST_POST) do
		if v == func then
			found = true
			break
		end
	end
	if not found then
		return nil, "Not allowed post to "..func
	end

	local cloud, err = snax.queryservice('cloud')
	if not cloud then
		return nil, err
	end

	local id = string.format(':APP_CLOUD_POST:%s-%0.2f]', self._app_name, skynet.time())
	cloud.post[func](id, ...)
	return true
end

local CLOUD_WHILTE_LIST_REQ = {}
---
-- 调用云端请求操作
-- @tparam func string 操作名称
-- @tparam ... args 操作参数
function sys:cloud_req(func, ...)
	local found = false
	for _, v in ipairs(CLOUD_WHILTE_LIST_REQ) do
		if v == func then
			found = true
		end
	end
	if not found then
		return nil, "Not allowed post to "..func
	end

	local cloud, err = snax.queryservice('cloud')
	if not cloud then
		return nil, err
	end
	local id = string.format(':APP_CLOUD_POST:%s-%0.2f]', self._app_name, skynet.time())
	return cloud.req[func](...)
end

local CFG_WHITE_LIST_CALL = {
	'SAVE',
}
---
-- 调用系统cfg服务操作
-- @tparam func string 操作名称
-- @tparam ... args 操作参数
function sys:cfg_call(func, ...)
	local found = false
	for _, v in ipairs(CLOUD_WHILTE_LIST_REQ) do
		if v == func then
			found = true
		end
	end
	if not found then
		return nil, "Not allowed post to "..func
	end

	local cfg, err = skynet.queryservice('CFG')
	if not cfg then
		return nil, err
	end
	return skynet.call(cfg, "lua", func, ...)
end

---
-- 设置事件触发阈值
-- @tparam count_per_min number 每分钟最大触发次数
function sys:set_event_threshold(count_per_min)
	self._data_api:_set_event_threshold(count_per_min)
end

---
-- API初始化函数
-- @tparam app_name string 应用实例名称
-- @tparam mgr_snax api 应用管理器snax对象
-- @tparam wrap_snax api 应用snax对象
function sys:initialize(app_name, mgr_snax, wrap_snax)
	self._mgr_snax = mgr_snax
	self._wrap_snax = wrap_snax
	self._app_name = app_name
	self._app_sn = nil
	self._logger = logger:new(app_name)
	self._data_api = api:new(app_name, mgr_snax, self._logger)
end

---
-- 清理当前对象
function sys:cleanup()
	if self._data_api then
		self._data_api:cleanup()
	end
end

return sys
