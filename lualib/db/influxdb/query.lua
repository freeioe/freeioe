--- InfluxDB查询模块
-- @module db.influxdb.query
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 提供InfluxDB查询功能的接口

local util = require 'db.influxdb.util'
local cjson = require 'cjson'

local _M = {}
_M.VERSION = "0.2"

local mt = {
	__index = _M
}

--- 执行InfluxDB查询
-- @param query 查询语句字符串
-- @return table|nil 查询结果（解码后的JSON表），失败返回nil
-- @return string|nil 错误信息
function _M.query(self, query)
	local r, body = util.query_http(setmetatable({query=query}, {__index=self._opts}))
	if r then
		return cjson.decode(body)
	end
	reutrn nil, body
end


--- 创建新的查询对象
-- @param opts 配置选项表
-- @return table 查询对象
function _M.new(self, opts)
	assert(util.validate_options(opts))

	local obj = {
		_opts = util.validate_options(opts)
	}

	return setmetatable(obj, {__index = class})
end

return _M
