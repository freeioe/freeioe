--- InfluxDB对象模块
-- @module db.influxdb.object
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 提供面向对象的InfluxDB写入接口，支持缓冲和批量写入

local _M = {}

local skynet = require 'skynet'
local lp   = require "db.influxdb.lineproto"
local util = require "db.influxdb.util"

local str_gsub = string.gsub
local str_rep  = string.rep
local str_sub  = string.sub
local str_find = string.find
local str_fmt  = string.format
local tbl_cat  = table.concat
local floor    = math.floor


_M.version = "0.2"

--- 对象元表
local mt = {
	__index = _M,
	__tostring = function(self)
		return str_fmt(
			"%s,%s,%s,%s,%s,%s",
			tostring(self._measurement),
			tostring(self._stamp),
			tostring(self._tag_cnt),
			tostring(tbl_cat(self._tag_set, '|')),
			tostring(self._field_cnt),
			tostring(tbl_cat(self._field_set, '|'))
		)
	end
}

--- 执行写入操作
-- @param msg 要写入的消息
-- @return boolean 成功返回true
-- @return string|nil 错误信息
function _M.do_write(self, msg)
	local proto = self.proto
	if proto == 'http' then
		return util.write_http(msg, self)
	elseif proto == 'udp' then
		return util.write_udp(msg, self.host, self.port)
	else
		return false, 'unknown proto'
	end
end

--- 添加标签
-- @param key 标签键
-- @param value 标签值
function _M.add_tag(self, key, value)
	local tag_cnt = self._tag_cnt + 1

	self._tag_cnt = tag_cnt

	-- TODO: 按键名排序标签
	self._tag_set[tag_cnt] = { [key] = value }
end

--- 添加字段
-- @param key 字段键
-- @param value 字段值
function _M.add_field(self, key, value)
	local field_cnt = self._field_cnt + 1

	self._field_cnt = field_cnt

	self._field_set[field_cnt] = { [key] = value }
end

--- 设置测量名称
-- @param measurement 测量名称
function _M.set_measurement(self, measurement)
	self._measurement = lp.quote_measurement(measurement)
end

--- 设置或获取时间戳
-- @param time 可选，指定时间戳
-- @return string 时间戳字符串
-- @description 如果不提供参数，根据精度设置自动生成时间戳
function _M.stamp(self, time)
	if time then
		if (type(time) == 'number') then
			self._stamp = time
			return
		else
			ERROR("invalid stamp type")
		end
	end

	local precision = self.precision
	if (precision == 'ms') then
		self._stamp = tostring(skynet.time() * 1000)
	elseif (precision == 's') then
		self._stamp = tostring(skynet.time())
	else
		self._stamp = ''
	end
end

--- 获取时间戳
-- @return string 时间戳字符串
-- @description 如果时间戳不存在则自动生成
function _M.timestamp(self)
	local stamp = self._stamp
	if not stamp then
		self:stamp()
		return self._stamp
	else
		return stamp
	end
end

--- 清空对象数据
-- @return boolean 成功返回true
function _M.clear(self)
	self._measurement = nil
	self._stamp = nil
	self._tag_cnt = 0
	self._tag_set = {}
	self._field_cnt = 0
	self._field_set = {}

	return true
end

--- 检查是否准备好缓冲
-- @return boolean 准备好返回true
-- @return string|nil 错误信息
function _M.buffer_ready(self)
	if not self._measurement then
		return false, 'no measurement'
	end

	if self._field_cnt == 0 then
		return false, 'no fields'
	end

	return true
end

--- 检查是否准备好刷新
-- @return boolean 准备好返回true
-- @return string|nil 错误信息
function _M.flush_ready(self)
	if self._measurement then
		return false, 'unbuffered measurement'
	end

	if self._field_cnt ~= 0 then
		return false, 'unbuffered fields'
	end

	if self._msg_cnt == 0 then
		return false, 'no buffered fields'
	end

	return true
end

--- 将当前数据添加到缓冲区
-- @return boolean 成功返回true
-- @return string|nil 错误信息
function _M.buffer(self)
	local ready, err_msg = self:buffer_ready()
	if not ready then
		return false, err_msg
	end

	self._tag_set   = lp.build_tag_set(self._tag_set)
	self._field_set = lp.build_field_set(self._field_set)

	self:timestamp()

	local msg = lp.build_line_proto_stmt(self)

	local msg_cnt = self._msg_cnt + 1
	self._msg_cnt = msg_cnt
	self._msg_buf[msg_cnt] = msg

	-- 清空条目以便下一次使用
	return self:clear()
end

--- 刷新缓冲区，写入所有数据
-- @return boolean 成功返回true
-- @return string|nil 错误信息
function _M.flush(self)
	local ready, err_msg = self:flush_ready()
	if not ready then
		return false, err_msg
	end

	local msg = tbl_cat(self._msg_buf, "\n")

	self._msg_cnt = 0
	self._msg_buf = {}

	return self:do_write(msg)
end

--- 立即写入当前数据
-- @return boolean 成功返回true
-- @return string|nil 错误信息
function _M.write(self)
	local ready, err_msg = self:buffer_ready()
	if not ready then
		return false, err_msg
	end

	self._tag_set   = lp.build_tag_set(self._tag_set)
	self._field_set = lp.build_field_set(self._field_set)

	self:timestamp()

	local ok, err_msg = self:do_write(lp.build_line_proto_stmt(self))
	if not ok then
		return false, err_msg
	end

	return self:clear()
end

--- 创建新的InfluxDB对象
-- @param opts 配置选项表
-- @return table|nil InfluxDB对象，失败返回nil
-- @return string|nil 错误信息
function _M.new(self, opts)
	local ok, err = util.validate_options(opts)
	if not ok then
		return false, err
	end

	local t = {
		-- 用户配置
		host      = opts.host,
		port      = opts.port,
		db        = opts.db,
		hostname  = opts.hostname,
		proto     = opts.proto,
		precision = opts.precision,
		ssl       = opts.ssl,
		auth      = opts.auth,

		-- 对象字段
		_tag_cnt   = 0,
		_tag_set   = {},
		_field_cnt = 0,
		_field_set = {},
		_msg_cnt   = 0,
		_msg_buf   = {},
	}

	return setmetatable(t, mt)
end

return _M
