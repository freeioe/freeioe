local _M = {}

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
			) end
}

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

function _M.add_tag(self, key, value)
	local tag_cnt = self._tag_cnt + 1

	self._tag_cnt = tag_cnt

	-- TODO sort tags by keys
	self._tag_set[tag_cnt] = { [key] = value }
end

function _M.add_field(self, key, value)
	local field_cnt = self._field_cnt + 1

	self._field_cnt = field_cnt

	self._field_set[field_cnt] = { [key] = value }
end

function _M.set_measurement(self, measurement)
	self._measurement = lp.quote_measurement(measurement)
end

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
		self._stamp = tostring(os.time() * 1000)
	elseif (precision == 's') then
		self._stamp = tostring(os.time())
	else
		self._stamp = ''
	end
end

function _M.timestamp(self)
	local stamp = self._stamp
	if not stamp then
		self:stamp()
		return self._stamp
	else
		return stamp
	end
end

function _M.clear(self)
	self._measurement = nil
	self._stamp = nil
	self._tag_cnt = 0
	self._tag_set = {}
	self._field_cnt = 0
	self._field_set = {}

	return true
end

function _M.buffer_ready(self)
	if not self._measurement then
		return false, 'no measurement'
	end

	if self._field_cnt == 0 then
		return false, 'no fields'
	end

	return true
end

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

	-- clear entries for another elt
	return self:clear()
end

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

function _M.new(self, opts)
	local ok, err = util.validate_options(opts)
	if not ok then
		return false, err
	end

	local t = {
		-- user opts
		host      = opts.host,
		port      = opts.port,
		db        = opts.db,
		hostname  = opts.hostname,
		proto     = opts.proto,
		precision = opts.precision,
		ssl       = opts.ssl,
		auth      = opts.auth,

		-- obj fields
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
