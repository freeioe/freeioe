local md5 = require 'md5'
local cjson = require 'cjson.safe'
local restful = require 'http.restful'
local ioe = require 'ioe'
local pkg = require 'pkg'

local _M = {}

_M.url_upload = '/pkg/file/upload'
_M.url_download = '/pkg/file/download'

---
-- Upload file data
-- @ treturn number ID
function _M.upload(filename, data, md5sum, timestamp, comment)
	local sum = md5sum or md5.sumhexa(data)
	local sn = ioe.id()
	local token = pkg.gen_token(sn)
	local timestamp = timestamp or os.time()

	local data = {
		filename = filename,
		device = sn,
		token = token,
		timestamp = timestamp,
		comment = comment or 'Device auto upload',
		data = data,
		md5 = sum,
	}

	local rest = restful:new(ioe.cnf_host_url())

	local status, body, recvheader = rest:post(_M.url_upload, nil, data)
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
	local sn = ioe.id()
	local token = pkg.gen_token(sn)

	local rest = restful:new(ioe.cnf_host_url())

	local query = { device = sn, token = token, id = id }
	local status, header, body = rest:get(_M.url_download, query)

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
