local skynet = require "skynet"

local lp   = require "influxdb.lineproto"
local util = require "influxdb.util"

local _M = {}
_M.VERSION = "0.2"

local mt = {
	__index = _M
}

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

function _M.clear(self)
	self._msg_buf = {}
end

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

function _M.flush(self)
	local msg = table.concat(self._msg_buf, "\n")
	self:clear()
	skynet.fork(_do_write, msg)
end

function _M.new(self, opts)
	assert(util.validate_options(opts))
	local t = {
		_opts = opts
		_msg_buf = {}
	}

	return setmetatable(t, mt)
end

return _M
