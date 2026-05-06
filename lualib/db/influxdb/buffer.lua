--- InfluxDB缓冲写入模块
-- @module db.influxdb.buffer
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06

local skynet = require "skynet"

local lp   = require "db.influxdb.lineproto"
local util = require "db.influxdb.util"

local _M = {}
_M.VERSION = "0.2"

local mt = {
	__index = _M
}

--- 执行写入操作
-- @param msg 要写入的消息
-- @return boolean 成功返回true，失败返回false
-- @return string|nil 错误信息
function _M._do_write(self, msg)
	local proto = self._opts.proto
	if proto == 'http' then
		return util.write_http(msg, self._opts)
	elseif proto == 'udp' then
		return util.write_udp(msg, self._opts)
	else
		return false, 'unknown proto'
	end
end

--- 清空消息缓冲区
function _M.clear(self)
	self._msg_buf = {}
end

--- 将数据添加到缓冲区
-- @param data 数据表，包含measurement、tags、fields字段
-- @return boolean 成功返回true
function _M.buffer(self, data)
	local influx_data = {
		_measurement = lp.quote_measurement(data.measurement),
		_tag_set = lp.build_tag_set(data.tags),
		_field_set = lp.build_field_set(data.fields),
		_stamp = os.time() * 1000
	}

	local msg = lp.build_line_proto_stmt(influx_data)

	table.insert(self._msg_buf, msg)

	return true
end

--- 刷新缓冲区，将所有缓冲的数据写入InfluxDB
function _M.flush(self)
	local msg = table.concat(self._msg_buf, "\n")
	self:clear()
	skynet.fork(_do_write, msg)
end

--- 创建新的缓冲区对象
-- @param opts 配置选项表
-- @return table 缓冲区对象
function _M.new(self, opts)
	assert(util.validate_options(opts))
	local t = {
		_opts = opts
		_msg_buf = {}
	}

	return setmetatable(t, mt)
end

return _M
