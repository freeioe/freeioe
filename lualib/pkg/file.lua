local md5 = require 'md5'
local cjson = require 'cjson.safe'
local restful = require 'http.restful'
local ioe = require 'ioe'

local _M = {}

---
-- Upload file data
-- @ treturn number ID
function _M.upload(filename, data, md5sum, timestamp, comment)
	local sum = md5sum or md5.sumhexa(data)
	local sn = ioe.id() or ioe.hw_id()
	local token = sn
	local timestamp = timestamp or os.time()

	local data = {
		filename = filename,
		sn = sn,
		token = token,
		timestamp = timestamp,
		comment = comment or 'Device auto upload'
		data = data,
		md5 = sum,
	}

	local rest = restful:new(iot.cnf_host_url())
	local url = '/pkg/file/upload'

	local status, body, recvheader = rest:post(url, nil, data)
	if status == 200 then
		local msg, err = cjson.decode(body)
		if not msg then
			return nil, err
		end
		if msg.code ~= 0 or not msg.data then
			return nil, msg.msg or "Message data missing"
		end
		if not msg.data.file then
			return nil, "File object missing"
		end
		return msg.data.file
	else
		return nil, body
	end
end

---
-- Get file data by version
--
function _M.download(id)
	local sn = ioe.id() or ioe.hw_id()
	local token = sn

	local rest = restful:new(iot.cnf_host_url())
	local url = '/pkg/file/download'

	local query = { sn = sn, token = token, id = id }
	local status, header, body = rest:get(url, query)

	local ret = {}
	if status == 200 then
		local msg, err = cjson.decode(body)
		if not msg then
			return nil, err
		end
		if msg.code ~= 0 or not msg.data then
			return nil, msg.msg or "Message data missing!"
		end
		local f = msg.data.file
		if not f then
			return nil, "File object missing"
		end

		return f.data, f.md5
	else
		return nil, body
	end
end

return _M
