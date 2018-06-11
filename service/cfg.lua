local skynet = require "skynet.manager"
local dc = require "skynet.datacenter"
local cjson = require "cjson.safe"
local md5 = require "md5"
local lfs = require 'lfs'
local restful = require 'restful'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'

local db_file = "cfg.json"
local md5sum = ""
local db_modification = 0
local db_restful = nil

local command = {}

function command.GET(app, ...)
	return dc.get('APPS', app, ...)
end

function command.SET(...)
	return dc.set('APPS', app, ...)
end

local function get_cfg_str()
	local cfg = {}
	cfg.cloud = dc.get("CLOUD")
	cfg.apps = dc.get("APPS")
	local str = cjson.encode(cfg)
	return str, md5.sumhexa(str)	
end

local function cfg_defaults()
	local ioe_sn = sysinfo.ioe_sn()
	return {
		ID = ioe_sn,
		HOST = "ioe.symgrid.com",
		PORT = 1883,
		KEEPALIVE = 60,
		DATA_UPLOAD = true,
		DATA_UPLOAD_PERIOD = 1000,
		EVENT_UPLOAD = 0,
		PKG_HOST_URL = "ioe.symgrid.com",
		SECRET = "ZGV2aWNlIGlkCg==",
	}
end

local function set_cfg_defaults(data)
	local defaults = cfg_defaults()
	for k,v in pairs(defaults) do
		data[k] = data[k] or v
	end
	if defaults.ID ~= sysinfo.unknown_ioe_sn then
		data.ID = defaults.ID
	end
	return data
end

local function load_cfg(path)
	log.info("::CFG:: Loading configuration...")
	local file, err = io.open(path, "r")
	if not file then
		dc.set("CLOUD", cfg_defaults())
		return nil, err
	end

	db_modification = tonumber(lfs.attributes(path, 'modification'))
	--print(db_modification, os.time())

	local str = file:read("*a")
	file:close()
	local sum = md5.sumhexa(str)
	local mfile, err = io.open(path..".md5", "r")
	if mfile then
		local md5s = mfile:read("*l")
		mfile:close()
		if md5s ~= sum then
			log.error("::CFG:: File md5 checksum error", md5s, sum)
			log.error("::CFG:: System is aborting, please correct this error manually!")
			skynet.sleep(100)
			skynet.abort()
		end
	else
		log.warning("::CFG:: Config File md5 file is missing, try create new one")
		local mfile, err = io.open(path..".md5", "w+")
		if mfile then
			mfile:write(sum)
			mfile:close()
		else
			log.warning("::CFG:: Failed to open md5 file for writing")
		end
	end

	db = cjson.decode(str) or {}

	db.cloud = set_cfg_defaults(db.cloud)
	dc.set("CLOUD", db.cloud)
	dc.set("APPS", db.apps)

	local _, csum = get_cfg_str()
	md5sum = csum or sum
end

local function save_cfg(path, content, content_md5sum)
	log.info("::CFG:: Saving configuration...")
	local file, err = io.open(path, "w+")
	if not file then
		return nil, err
	end
	local mfile, err = io.open(path..".md5", "w+")
	if not mfile then
		return nil, err
	end
	db_modification = os.time()
	file:write(content)
	file:close()

	mfile:write(content_md5sum)
	mfile:close()

	return true
end

local function save_cfg_cloud(content, content_md5sum)
	local id = dc.get("CLOUD", "ID")
	if id and db_restful then
		local url = "ioe_device_conf/"..id
		local c = {
			timestamp = db_modification,
			data = content,
			md5 = content_md5sum,
		}
		local status, body = db_restful:post(url, c)
		if not status and status ~= 200 then
			log.warning("::CFG:: Saving cloud config failed", status or -1, body)
		end
	end
end

local function load_cfg_cloud()
	local id = dc.get("CLOUD", "ID")
	if id and db_restful then
		local status, body = db_restful:get("ioe_device_conf/"..id.."/timestamp")
		if status ~= 200 then
			log.warning("::CFG:: Get cloud config failed", status or -1, body)
			return
		end
		tm = tonumber(body)
		if tm and tm > db_modification then
			log.notice("::CFG:: Configuration in cloud is newer")
			local status, content = db_restful:get("ioe_device_conf/"..id.."/content")
			if status ~= 200 then
				log.warning("::CFG:: Get cloud config failed", status or -1, body)
			end
			local status, md5sum = db_restful:get("ioe_device_conf/"..id.."/md5")
			if status ~= 200 then
				log.warning("::CFG:: Get cloud config failed", status or -1, body)
			end
			local sum = md5.sumhexa(content)
			if sum ~= md5sum then
				log.warning("::CFG:: MD5 Checksum error", sum, md5sum)
			end
			local r, err = save_cfg(db_file, str, sum)
			if not r  then
				log.warning("::CFG:: Saving configurtaion failed", err)
			end
			-- Quit skynet
			skynet.abort()
		end
		if tm and tm <= db_modification then
			log.info("::CFG:: Local configuration is newer")
		end
	end
end

function command.SAVE(opt_path)
	local str, sum = get_cfg_str()
	if sum ~= md5sum then
		local r, err = save_cfg(opt_path or db_file, str, sum)
		if r then
			md5sum = sum
		end
		save_cfg_cloud(str, sum)
		os.execute('sync')
	end
end

function command.CLEAR()
	db = {}
end

local function init_restful()
	local cfg = dc.get("CLOUD", "CFG")
	if cfg and cfg.ENABLE then
		db_restful = restful:new(cfg.HOST, cfg.TIMEOUT)
	end
end

skynet.start(function()
	load_cfg(db_file)
	init_restful()

	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	skynet.register "CFG"

	skynet.timeout(50, function()
		load_cfg_cloud()
	end)
	skynet.fork(function()
		while true do
			command.SAVE()
			skynet.sleep(500)
		end
	end)
end)
