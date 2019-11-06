local skynet = require 'skynet'
local snax = require 'skynet.snax'
local ubus = require 'ubus'
local crypt = require 'skynet.crypt'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'
local app_api = require 'app.api'
local ioe = require 'ioe'

local api = nil
local bus = nil

--[[
-- Api Handler
--]]
local Handler = {
	on_comm = function(app, sn, dir, ts, ...)
		--local hex = crypt.hexencode(table.concat({...}, '\t'))
		--hex = string.gsub(hex, "%w%w", "%1 ")
		local content = crypt.base64encode(table.concat({...}, '\t'))
	end,
	on_event = function(app, sn, level, type_, info, data, timestamp)
	end,
}

function response.ping()
	return "PONG"
end

function create_methods(bus)
	return {
		ping = { 
			function(req, msg, resp)
				resp({id=msg.id or 'empty id', msg=msg.msg or 'empty message' })
				return ubus.STATUS_OK
			end, { id = ubus.INT32, msg = ubus.STRING }
		},
		--[[
		test = {
			function(req, msg)
				print('on test')
				return ubus.STATUS_OK
			end, { id = ubus.INT32, msg = ubus.STRING }
		},
		]]--
		info = {
			function(req, msg, response)
				local info = {}
				info.version = sysinfo.version()
				info.skynet_version = sysinfo.skynet_version()
				info.firmware_version = sysinfo.firmware_version()
				info.cpu_arch = sysinfo.cpu_arch()
				info.platform = sysinfo.platform()
				info.id = ioe.id()
				info.hw_id = ioe.hw_id()
				info.beta = ioe.beta()
				response(info)
				return ubus.STATUS_OK
			end, {}
		},
		cloud = {
			function(req, msg, response)
				local dc = require 'skynet.datacenter'
				local cloud = snax.queryservice('cloud')
				local info = {}
				info.host = dc.get("CLOUD", "HOST")
				local online, last, msg = cloud.req.get_status()
				info.mqtt = {
					online = online,
					last = last,
					msg = msg
				}
				response(info)
				return ubus.STATUS_OK
			end, {}
		},
		apps = {
			function(req, msg, response)
				local dc = require 'skynet.datacenter'
				local apps = dc.get('APPS') or {}
				local appmgr = snax.queryservice('appmgr')
				local applist = appmgr.req.list()
				for k, v in pairs(apps) do
					v.running = applist[k] and applist[k].inst or nil
					v.running = v.running and true or false
					v.version = math.floor(tonumber(v.version) or 0)
					v.auto = math.floor(tonumber(v.auto or 1))
				end

				response(apps)
				return ubus.STATUS_OK
			end, {}
		},
		start_app = {
			function(req, msg, response)
				if not msg.inst then
					return ubus.INVALID_ARGUMENT
				end
				local appmgr = snax.queryservice('appmgr')
				local r, err = appmgr.req.start(msg.inst)
				response( {result = r, msg = err} )
				return ubus.STATUS_OK
			end, {inst=ubus.STRING}
		},
		stop_app = {
			function(req, msg, response)
				if not msg.inst then
					return ubus.INVALID_ARGUMENT
				end
				local appmgr = snax.queryservice('appmgr')
				local r, err = appmgr.req.stop(msg.inst, 'stop from ubus')
				response( {result = r, msg = err} )
				return ubus.STATUS_OK
			end, {inst=ubus.STRING}
		},
		data = {
			function(req, msg, response)
				local device = msg.device
				if device then
					local dev, err = api:get_device(device)
					if dev then
						response(dev:data())
					end
				else
					local dc = require 'skynet.datacenter'
					response(dc.get('INPUT') or {})
				end
				return ubus.STATUS_OK
			end, {device=ubus.STRING}
		},
		upgrade = {
			function(req, msg, response)
				local data = {
					version = msg.version,
					no_ack = 1,
				}
				if msg.skynet then
					data.skynet = {
						version = data.skynet
					}
				end
				local r, err = skynet.call(".upgrader", "lua", "upgrade_core", req.peer, data)
				response( {result = r, msg = err} )
				return ubus.STATUS_OK
			end, {version=ubus.INT32, skynet=ubus.INT32}
		},
		upgrade_app = {
			function(req, msg, response)
				if not msg.inst then
					return ubus.INVALID_ARGUMENT
				end
				local data = {
					inst = msg.inst,
					version = msg.version
				}

				local r, err = skynet.call(".upgrader", "lua", "upgrade_app", req.peer, data)
				response( {result = r, msg = err} )
				return ubus.STATUS_OK
			end, {inst=ubus.STRING, version=ubus.INT32}
		},
		install_app = {
			function(req, msg, response)
				if not msg.inst or not msg.name then
					return ubus.INVALID_ARGUMENT
				end
				local data = {
					inst = msg.inst,
					version = msg.version,
					name = msg.name,
					conf = msg.conf
				}

				local r, err = skynet.call(".upgrader", "lua", "install_app", req.peer, data)
				response( {result = r, msg = err} )
				return ubus.STATUS_OK
			end, {inst=ubus.STRING, name=ubus.STRING,version=ubus.INT32,conf=ubus.TABLE}
		},
		option_app = {
			function(req, msg, response)
				if not msg.inst or not msg.option or msg.value == nil then
					return ubus.INVALID_ARGUMENT
				end
				local appmgr = snax.queryservice('appmgr')
				local r, err = appmgr.req.app_option(msg.inst, msg.option, msg.value)
				response( {result = r, msg = err} )
				return ubus.STATUS_OK
			end, {inst=ubus.STRING, option=ubus.STRING, value=ubus.STRING}
		}
	}
end

function init(...)
	bus = ubus:new()
	bus:connect(...)
	--bus:connect("172.30.19.103", 11000)
	--bus:connect("172.30.11.230", 11000)
	--bus:connect("/tmp/ubus.sock")
	local s, err = bus:status()
	if not s then
		log.error('::UBUS:: Cannot connect to ubusd', err, ...)
		return
	end

	local methods = create_methods(bus)
	local obj_id, obj_type = bus:add('freeioe', methods, function(...)
		print('subscribe cb', ...)
	end)

	log.notice("::UBUS:: System ubus service started!")
	skynet.fork(function()
		api = app_api:new('UBUS')
		api:set_handler(Handler)
	end)
end

function exit(...)
	log.notice("::UBUS:: System ubus service stoped!")
end
