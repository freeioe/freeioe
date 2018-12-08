local skynet = require 'skynet'
local socket = require 'skynet.socket'
local socket_driver = require 'skynet.socketdriver'
local lsocket = require 'lsocket'
local class = require 'middleclass'
local ublob = require 'ubox.blob'
local ublob_buf = require 'ubox.blob_buf'
local ublob_msg = require 'ubox.blob_msg'
local umsg = require 'ubus.msg'
local basexx = require 'basexx'
local cjson = require 'cjson'

local ubus = class('ubus')

ubus.static.UNIX_SOCKET = '/var/run/ubus.sock'

ubus.static.ATTR_UNSPEC = 0
ubus.static.ATTR_STATUS = 1
ubus.static.ATTR_OBJPATH = 2
ubus.static.ATTR_OBJID = 3
ubus.static.ATTR_METHOD = 4
ubus.static.ATTR_OBJTYPE = 5
ubus.static.ATTR_SIGNATURE = 6
ubus.static.ATTR_DATA = 7
ubus.static.ATTR_TARGET = 8
ubus.static.ATTR_ACTIVE = 9
ubus.static.ATTR_NO_REPLY = 10
ubus.static.ATTR_SUBSCRIBERS = 11
ubus.static.ATTR_USER = 12
ubus.static.ATTR_GROUP = 13
ubus.static.ATTR_MAX = 14

ubus.static.MONITOR_CLIENT = 0
ubus.static.MONITOR_PEER = 1
ubus.static.MONITOR_SEND = 2
ubus.static.MONITOR_SEQ = 3
ubus.static.MONITOR_TYPE = 4
ubus.static.MONITOR_DATA = 5
ubus.static.MONITOR_MAX = 6

ubus.static.STATUS_OK = 0
ubus.static.STATUS_INVALID_COMMAND = 1
ubus.static.STATUS_INVALID_AGRUMENT = 2
ubus.static.STATUS_METHOD_NOT_FOUND = 3
ubus.static.STATUS_NOT_FOUND = 4
ubus.static.STATUS_NO_DATA = 5
ubus.static.STATUS_PERMISSION_DENIED = 6
ubus.static.STATUS_TIMEOUT = 7
ubus.static.STATUS_NOT_SUPPORTED = 8
ubus.static.STATUS_UNKNOWN_ERROR = 9
ubus.static.STATUS_CONNECTION_FAILED = 10
ubus.static.STATUS_LAST = 11

ubus.static.OBJECT_EVENT = 1
ubus.static.OBJECT_ACL = 2
ubus.static.OBJECT_MONITOR = 3
ubus.static.OBJECT_MAX = 1024

ubus.static.UNSPEC = ublob_msg.UNSPEC
ubus.static.ARRAY = ublob_msg.ARRAY
ubus.static.TABLE = ublob_msg.TABLE
ubus.static.STRING = ublob_msg.STRING
ubus.static.INT64 = ublob_msg.INT64
ubus.static.INT32 = ublob_msg.INT32
ubus.static.INT16 = ublob_msg.INT16
ubus.static.INT8 = ublob_msg.INT8
ubus.static.DOUBLE = ublob_msg.DOUBLE
ubus.static.BOOL = ublob_msg.BOOL


local blob_info = {
	[ubus.ATTR_UNSPEC] = { type = ublob.ATTR_UNSPEC },
	[ubus.ATTR_STATUS] = { type = ublob.ATTR_INT32 },
	[ubus.ATTR_OBJPATH] = { type = ublob.ATTR_STRING },
	[ubus.ATTR_OBJID] = { type = ublob.ATTR_INT32 },
	[ubus.ATTR_METHOD] = { type = ublob.ATTR_STRING },
	[ubus.ATTR_OBJTYPE] = { type = ublob.ATTR_INT32 },
	[ubus.ATTR_SIGNATURE] = { type = ublob.ATTR_NESTED },
	[ubus.ATTR_DATA] = { type = ublob.ATTR_NESTED },
	[ubus.ATTR_TARGET] = { type = ublob.ATTR_INT32 },
	[ubus.ATTR_ACTIVE] = { type = ublob.ATTR_INT8 },
	[ubus.ATTR_NO_REPLY] = { type = ublob.ATTR_INT8 },
	[ubus.ATTR_SUBSCRIBERS] = { type = ublob.ATTR_NESTED },
	[ubus.ATTR_USER] = { type = ublob.ATTR_STRING },
	[ubus.ATTR_GROUP] = { type = ublob.ATTR_STRING },
}

ubus.static.blob_info = blob_info

local monitor_blob_info = {
	[ubus.MONITOR_CLIENT] = { type = ublob.ATTR_INT32 },
	[ubus.MONITOR_PEER] = { type = ublob.ATTR_INT32 },
	[ubus.MONITOR_SEND] = { type = ublob.ATTR_INT8 },
	[ubus.MONITOR_TYPE] = { type = ublob.ATTR_INT32 },
	[ubus.MONITOR_DATA] = { type = ublob.ATTR_NESTED },
}

ubus.static.monitor_blob_info = monitor_blob_info

function ublob_buf:add_ubus_data(data)
	local msg_buf = ublob_buf:new(ubus.blob_info, 0)
	for k, v in pairs(data or {}) do
		local msg = ublob_msg:from_lua(ubus.blob_info, k, v)
		msg_buf:add(msg:blob())
	end
	self:add_buf(ubus.ATTR_DATA, msg_buf)
end

function ublob_buf:add_ubus_signature(data)
	local msg_buf = self:add_nested(ubus.ATTR_SIGNATURE)
	for k, v in pairs(data or {}) do
		local msg = ublob_msg:from_lua(ubus.blob_info, k, v)
		msg_buf:add(msg:blob())
	end
end

--- Connection points to new
function ubus.static:connect(...)
	return self:new(...)
end

function ubus:initialize(timeout)
	self.__timeout = (timeout or 30) * 100
	self.__req_seq = 1
	self.__thread = {}
	self.__result = {}
	self.__result_code = {}
	self.__result_data = {}
	self.__objects = {}
end

function ubus:connect(addr, port)
	local addr  = addr or ubus.UNIX_SOCKET
	local client, err = lsocket.connect(addr, port)
	if not client then
		return nil, err
	end
	lsocket.select(nil, {client})
	local ok, err = client:status()
	if not ok then
		return nil, err
	end

	local sock = socket.bind(client:getfd())
	socket_driver.nodelay(sock)

	local msg, err = umsg:read_sock(sock, ubus.blob_info)
	if not msg then
		return nil, err
	end
	if msg:type() ~= umsg.HELLO then
		return nil, "Invalid hello message type: "..msg:type()
	end

	while self.__dispatch_thread do
		skynet.yield()
	end

	self.__local_id = msg:peer()
	self.__client = client
	self.__sock = sock
	self.__dispatch_thread = skynet.fork(function()
		self:dispatch_function()
		-- clear dispatch_thread
		self.__dispatch_thread = nil
	end)


	return true, "Connected!"
end

-- Socket status
function ubus:status()
	if not self.__client then
		return nil, "Socket client not available"
	end
	return self.__client:status()
end

function ubus:start_request(msg_id, ubuf, peer)
	assert(msg_id >= 0 and msg_id < umsg.MSG_LAST)
	assert(ubuf)
	local peer = peer or 0

	if not self.__client then
		return nil, "Not connected!"
	end

	local seq = self.__req_seq
	local msg = umsg:new(msg_id, seq, peer, ubuf)
	self.__req_seq = self.__req_seq + 1
	
	--print("Send", seq, basexx.to_hex(tostring(msg)))
	-- TODO:
	--local r, err = socket.write(self.__sock, tostring(msg))
	local r, err = self.__client:send(tostring(msg))
	if r then
		self.__thread[seq] = coroutine.running()
	end
	return r, err
end

function ubus:send_ubuf(msg_id, ubuf, peer, seq)
	local msg = umsg:new(msg_id, seq, peer, ubuf)
	return self.__client:send(tostring(msg))
end

function ubus:dispatch_function()
	while self.__sock do
		local msg, err = umsg:read_sock(self.__sock, ubus.blob_info)
		if not msg then
			skynet.error(err)
			break
		end
		self:dispatch_response(msg)
	end
end

function ubus:dispatch_response(msg)
	print('response', msg:seq(), msg:type(), msg:peer()) --, msg:data())

	if msg:type() == umsg.DATA then
		local co = self.__thread[msg:seq()]
		if not co then
			return nil, "No request thread found for "..msg:seq()
		end
		--print('DATA------------')
		--msg:dbg_print()
		--print('DATA------------')
		
		local data = self.__result_data[co] or {}
		table.insert(data, msg)
		self.__result_data[co] = data
		return
	end
	if msg:type() == umsg.STATUS then
		local co = self.__thread[msg:seq()]
		if not co then
			return nil, "No request thread found for "..msg:seq()
		end
		local status = assert(msg:data(ubus.ATTR_STATUS))
		--print('STATUS', status)
		self.__result[co] = true
		self.__result_code[co] = status
		skynet.wakeup(co)
		return
	end

	if msg:type() == umsg.MONITOR then
		return self:process_monitor_messsage(msg)
	end

	local obj_id = msg:data(ubus.ATTR_OBJID)
	if not obj_id then
		return
	end
	if msg:type() == umsg.INVOKE then
		return self:__request(self.process_invoke_message, obj_id, msg)
	end
	if msg:type() == umsg.UNSUBSCRIBE then
		return self:__request(self.process_unsub_message, obj_id, msg)
	end
	if msg:type() == umsg.NOTIFY then
		return self:__request(self.process_notify_message, obj_id, msg)
	end
end

function ubus:__fire_status(status, obj_id, peer, seq)
	assert(peer and seq)
	local buf = ublob_buf:new(ubus.blob_info, 0)
	buf:add_int32(ubus.ATTR_STATUS, status)
	buf:add_int32(ubus.ATTR_OBJID, obj_id)
	return self:send_ubuf(umsg.STATUS, buf, peer, seq)
end

function ubus:__request(func, obj_id, msg)
	local ret, data = func(self, obj_id, msg)

	local no_reply = msg:data(ubus.ATTR_NO_REPLY)
	if no_reply and no_reply ~= 0 then
		return
	end

	if ret ~= STATUS_OK then
		return self:__fire_status(ret, obj_id, msg:peer(), msg:seq())
	else
		local buf = ublob_buf:new(ubus.blob_info, 0)
		buf:add_int32(ubus.ATTR_OBJID, obj_id)
		buf:add_nested(ubus.ATTR_DATA, data)
		local r, err = self:send_ubuf(umsg.DATA, buf, msg:peer(), msg:seq())
		if not r then
			return nil, err
		end
		return self:__fire_status(ubus.STATUS_OK, obj_id, msg:peer(), msg:seq())
	end
end

function ubus:process_obj_message(obj_id, method, msg)
	local obj = self.__objects[obj_id]
	if not obj then
		return STATUS_NOT_FOUND
	end

	local func = obj.methods[method] or obj.methods.__notify_cb
	if not func then
		return STATUS_METHOD_NOT_FOUND
	end

	local data = msg:data(ubus.ATTR_DATA)
	local items = {}
	for k,v in pairs(data) do
		--print(basexx.to_hex(tostring(v)))
		local msg = assert(ublob_msg:from_blob(ubus.blob_info, v))

		local name, val = msg:msg2lua() 
		if string.len(name) > 0 then
			items[name] = val
		else
			table.insert(items, val)
		end
	end
	local acl =  {}
	acl.user = msg:data(ubus.ATTR_USER)
	acl.group = msg:data(ubus.ATTR_GROUP)
	acl.object = self.__objects[obj_id].path

	local req = {
		peer = umsg:peer(),
		seq = umsg:seq(),
		object = obj_id,
		acl = acl,
	}
	return m[1](req, data, m[3])
end

function ubus:process_invoke_message(obj_id, msg)
	local method = msg:data(ubus.ATTR_METHOD)
	if not method then
		return STATUS_INVALID_ARGUMENT
	end
	return self:process_obj_message(obj_id, method, msg)
end

function ubus:process_unsub_message(obj_id, msg)
	return self:process_obj_message(obj_id, '__remove_cb', msg)
end

function ubus:process_notify_message(obj_id, msg)
	return self:process_obj_message(obj_id, '__subscribe_cb', msg)
end

function ubus:request(request_id, buf, peer)
	local r, err = self:start_request(request_id, buf, peer)
	if not r then
		return nil, err
	end

	local co = coroutine.running()
	skynet.wait(co)
	
	local result = self.__result[co]
	local result_code = self.__result_code[co]
	local result_data = self.__result_data[co]
	self.__result[co] = nil
	self.__result_code[co] = nil
	self.__result_data[co] = nil
	if not result then
		return nil, result_data or "Failed or aborted"
	end
	if result_code == ubus.STATUS_OK then
		return result_data
	end

	return nil, "Status code is "..result_code, result_data
end

-- List current avaiable object namespaces
function ubus:objects(path)
	local buf = ublob_buf:new(ubus.blob_info, 0)
	if path and string.len(path) > 0 then
		buf:add_string(ubus.ATTR_OBJPATH, path)
	end

	local objs, err = self:request(umsg.LOOKUP, buf, 0)
	if not objs then
		return nil, err
	end

	local results = {}
	for _, v in ipairs(objs) do
		local id = v:data(ubus.ATTR_OBJID)
		local path = v:data(ubus.ATTR_OBJPATH)
		local type_id = v:data(ubus.ATTR_OBJTYPE)
		local signature = v:data(ubus.ATTR_SIGNATURE)

		local items = {}
		for k,v in pairs(signature) do
			local msg = assert(ublob_msg:from_blob(ubus.blob_info, v))

			local name, val = msg:msg2lua() 
			items[name] = val
		end

		table.insert(results, {
			id = id,
			path = path,
			type = type_id,
			signature = items 
		})
	end
	--print(cjson.encode(results))

	return results
end

function ubus:lookup_id(path)
	local ret = self:objects(path)
	if path then
		for _, v in ipairs(ret) do
			--print(v.path, path)
			if v.path == path then
				return v.id
			end
		end
		return nil, "No id for path "..path
	end

	local ids = {}
	for _, v in ipairs(ret) do
		ids[v.path] = v.id
	end

	return ids
end


-- Add object
--  return ubus object
function ubus:add(path, methods, subscribe_cb)
	assert(path and methods)

	local meta = {}
	for k, v in pairs(methods or {}) do
		meta[k] = v[2]
	end

	local buf = ublob_buf:new(ubus.blob_info, 0)
	buf:add_string(ubus.ATTR_OBJPATH, path)
	buf:add_ubus_signature(meta)

	local objs, err = self:request(umsg.ADD_OBJECT, buf, 0)
	if not objs then
		return nil, err
	end

	assert(#objs == 1)
	local v = objs[1]
	local rid = v:data(ubus.ATTR_OBJID)
	local rtype = v:data(ubus.ATTR_OBJTYPE)

	v:dbg_print()

	if subscribe_cb then
		-- Call this when notified that someone is subscribe on this object
		methods.__subscribe_cb = subscribe_cb
	end

	self.__objects[rid] = {
		path = path,
		methods = methods,
	}

	return rid, rtype
end

-- Remove ubus object
function ubus:remove(id)
	local buf = ublob_buf:new(ubus.blob_info, 0)
	buf:add_int32(ubus.ATTR_OBJID, id)

	local objs, err = self:request(umsg.REMOVE_OBJECT, buf, 0)
	if not objs then
		return nil, err
	end

	self.__objects[id] = nil

	return true
end

-- Notify object
function ubus:notify(id, method, params)
	local buf = ublob_buf:new(ubus.blob_info, 0)
	buf:add_int32(ubus.ATTR_OBJID, id)
	buf:add_string(ubus.ATTR_METHOD, method)
	buf:add_ubus_data(params)
	buf:add_int8(ubus.ATTR_NO_REPLY, 1)

	return self:request(umsg.NOTIFY, buf, id)
end

-- Call method
function ubus:call(path, method, params)
	assert(path and method)
	local id, err = self:lookup_id(path)
	if not id then
		return nil, err
	end
	
	local buf = ublob_buf:new(ubus.blob_info, 0)
	buf:add_int32(ubus.ATTR_OBJID, id)
	buf:add_string(ubus.ATTR_METHOD, method)
	buf:add_ubus_data(params)

	local objs, err = self:request(umsg.INVOKE, buf, id)
	if not objs then
		return nil, err
	end

	local results = {}
	for _, v in ipairs(objs) do
		local rid = v:data(ubus.ATTR_OBJID)
		local rdata = v:data(ubus.ATTR_DATA)
		-- print('rid', rid, 'id', id)

		local items = {}
		for k,v in pairs(rdata) do
			--print(basexx.to_hex(tostring(v)))
			local msg = assert(ublob_msg:from_blob(ubus.blob_info, v))

			local name, val = msg:msg2lua() 
			if string.len(name) > 0 then
				items[name] = val
			else
				table.insert(items, val)
			end
		end
		results[rid] = items
	end
	if not results[id] then
		return nil, "Result does not contains reply from path "..path.. " which id is "..id
	end
	return results[id]
end

function ubus:close()
	if self.__sock then
		socket.close(self.__sock)
		self.__sock = nil
		self.__client = nil
	end
end

function ubus:subscribe(path, on_notify, on_remove)
	--- Lookup for path and then subscribe
	local target_id, err = self:lookup_id(path)
	if not target_id then
		return nil, err
	end

	local id = self:add(path, {__notify_cb = on_notify, __remove_cb = on_remove})

	local buf = ublob_buf:new(ubus.blob_info, 0)
	buf:add_int32(ubus.ATTR_OBJID, id)
	buf:add_int32(ubus.ATTR_TARGET, target_id)
	return self:request(umsg.SUBSCRIBE, buf, 0)
end

function ubus:__gc()
	self:clsoe()
end

return ubus
