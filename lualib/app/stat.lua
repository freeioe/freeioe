--- 设备统计模块
--
-- 本模块为设备提供统计跟踪和报告功能
-- 管理通信性能监控的计数器和比率
--
-- 标准统计属性：
--   status - 当前设备状态
--   success_ratio - 成功操作比率（百分比）
--   error_ratio - 错误操作比率（百分比）
--   packets_in - 接收的数据包总数
--   packets_out - 发送的数据包总数
--   packets_error - 数据包错误总数
--   bytes_in - 接收的字节总数
--   bytes_out - 发送的字节总数
--   bytes_error - 字节错误总数
---

local skynet = require 'skynet'
local ioe = require 'ioe'
local class = require 'middleclass'
local mc = require 'skynet.multicast'
local dc = require 'skynet.datacenter'

--- 统计类
--
-- 管理设备统计，支持自动持久化和多播发布更新
---
local stat = class("APP_MGR_DEV_API")

--- 标准属性列表
local standard_props = {
	'status',         -- 状态
	'success_ratio', -- 成功率
	'error_ratio',   -- 错误率
	'packets_in',    -- 接收包数
	'packets_out',   -- 发送包数
	'packets_error', -- 错误包数
	'bytes_in',      -- 接收字节数
	'bytes_out',     -- 发送字节数
	'bytes_error'    -- 错误字节数
}

---
-- 初始化设备的统计实例
-- @param api: 父API对象
-- @param sn: 设备序列号
-- @param name: 统计名称（例如'comm'、'data'）
-- @param readonly: 如果为true则表示这是一个访客（只读）统计对象
---
function stat:initialize(api, sn, name, readonly)
	self._api = api
	self._sn = sn
	self._name = name
	if readonly then
		self._app_name = dc.get('DEV_IN_APP', sn) or api._app_name
	else
		self._app_name = api._app_name
	end
	self._stat_chn = api._stat_chn
	self._readonly = readonly
	self._stat_map = {}
	for _,v in ipairs(standard_props) do
		self._stat_map[v] = true
		dc.set('STAT', self._sn, self._name, v, 0)
	end
end

---
-- 内部清理统计引用
---
function stat:_cleanup()
	self._readonly = true
	self._stat_chn = nil
	self._app_name = nil
	self._name = nil
	self._sn = nil
	self._api = nil
end

---
-- 清理统计对象
-- 对于所有者统计对象，清除内部引用
---
function stat:cleanup()
	if self._readonly then
		return
	end
	local sn = self._sn

	self:_cleanup()
end

---
-- 获取统计属性值
-- @param prop: 属性名称
-- @return: 属性值，未找到时返回nil
---
function stat:get(prop)
	return dc.get('STAT', self._sn, self._name, prop)
end

---
-- 将统计属性重置为零
-- @param prop: 属性名称
-- @return: 设置结果
---
function stat:reset(prop)
	return self:set(prop, 0)
end

---
-- 按值递增统计属性
-- @param prop: 属性名称
-- @param value: 递增量（必须为正数）
-- @return: 成功返回true，失败返回nil和错误信息
---
function stat:inc(prop, value)
	assert(not self._readonly, "Device statistics owner issue")
	assert(prop and value)
	if not self._stat_map[prop] then
		return nil, string.format("Statistics property [%s] is not valid. ", prop)
	end

	value = value + self:get(prop)

	dc.set('STAT', self._sn, self._name, prop, value)
	self._stat_chn:publish(self._app_name, self._sn, self._name, prop, value, ioe.time())
	return true
end

---
-- 将统计属性设置为特定值
-- @param prop: 属性名称
-- @param value: 新的属性值
-- @return: 成功返回true，失败返回nil和错误信息
---
function stat:set(prop, value)
	assert(not self._readonly, "Device statistics owner issue")
	assert(prop and value)
	if not self._stat_map[prop] then
		return nil, string.format("Statistics property [%s] is not valid. ", prop)
	end

	dc.set('STAT', self._sn, self._name, prop, value)
	self._stat_chn:publish(self._app_name, self._sn, self._name, prop, value, ioe.time())
	return true
end

return stat
