--- InfluxDB行协议(Line Protocol)处理模块
-- @module db.influxdb.lineproto
-- @author FreeIOE
-- @license MIT
-- @release 2025.05.06
-- @description 根据InfluxDB行协议规范构建和转义数据
-- 参考文档: https://docs.influxdata.com/influxdb/v1.0/write_protocols/line_protocol_reference/

local _M = {}

local str_gsub = string.gsub
local str_find = string.find
local str_fmt  = string.format
local tbl_cat  = table.concat

local warn = function(msg)
	return DEBUG('WARN', msg)
end

--- 布尔值匹配模式列表
local bool_strs = { '^t$', '^T$', '^true$', '^True$', '^TRUE$', '^f$', '^F$', '^false$', '^False$', '^FALSE$' }

_M.version = "0.2"

--- 转义字段值
-- @param value 字段值（数字、字符串或布尔值）
-- @return string 转义后的值
-- @description 数字和布尔值直接返回，字符串值中的双引号会被转义
function _M.quote_field_value(value)
	-- 数字类型检查（浮点数或整数）
	if type(value) ~= 'string' or str_find(value, '^%d+i$') then
		return value
	end

	-- 布尔值检查
	for i = 1, 10 do
		if str_find(value, bool_strs[i]) then
			return value
		end
	end

	-- 转义字符串中的双引号
	value = str_gsub(value, '"', '\\"')
	return str_fmt('"%s"', value)
end

--- 转义字段键
-- @param value 字段键名
-- @return string 转义后的键名
-- @description 转义逗号、等号和空格
function _M.quote_field_key(value)
	value = str_gsub(value, ',', '\\,')
	value = str_gsub(value, '=', '\\=')
	value = str_gsub(value, ' ', '\\ ')

	return value
end

--- 转义标签部分（键或值）
-- @param value 标签键或值
-- @return string 转义后的值
-- @description 转义逗号、等号和空格
function _M.quote_tag_part(value)
	value = str_gsub(value, ',', '\\,')
	value = str_gsub(value, '=', '\\=')
	value = str_gsub(value, ' ', '\\ ')

	return value
end

--- 转义测量名称
-- @param value 测量名称
-- @return string 转义后的测量名称
-- @description 转义逗号和空格
function _M.quote_measurement(value)
	value = str_gsub(value, ',', '\\,')
	value = str_gsub(value, ' ', '\\ ')

	return value
end

--- 构建标签集合
-- @param tags 标签数组，每个元素是key-value对
-- @return table|nil 构建的标签集合数组，失败返回nil
function _M.build_tag_set(tags)
	if not tags then
		return {}
	end

	if type(tags) ~= 'table' then
		warn('Invalid tags table')
		return nil
	end

	local tag_set = {}

	for i = 1, #tags do
		local tag      = tags[i]
		local key, val = next(tag)

		key = _M.quote_tag_part(key)
		val = _M.quote_tag_part(val)

		tag_set[i] = str_fmt("%s=%s", key, val)
	end

	-- TODO: 按键名排序标签
	return tag_set
end

--- 构建字段集合
-- @param fields 字段数组，每个元素是key-value对
-- @return table|nil 构建的字段集合数组，失败返回nil
function _M.build_field_set(fields)
	if type(fields) ~= 'table' then
		warn('Invalid fields table')
		return nil
	end

	local field_set = {}

	for i = 1, #fields do
		local field    = fields[i]
		local key, val = next(field)

		key = _M.quote_field_key(key)
		val = _M.quote_field_value(val)

		field_set[i] = str_fmt("%s=%s", key, val)
	end

	return field_set
end

--- 构建完整的行协议语句
-- @param influx 包含_measurement、_tag_set、_field_set、_stamp的数据表
-- @return string 行协议字符串
-- @description 格式: measurement[,tag_set] field_set timestamp
function _M.build_line_proto_stmt(influx)
	local measurement = influx._measurement
	local tag_set     = tbl_cat(influx._tag_set, ',')
	local field_set   = tbl_cat(influx._field_set, ',')
	local timestamp   = influx._stamp

	if (tag_set ~= '') then
		return str_fmt("%s,%s %s %s", measurement, tag_set, field_set, timestamp)
	else
		return str_fmt("%s %s %s", measurement, field_set, timestamp)
	end
end

return _M
