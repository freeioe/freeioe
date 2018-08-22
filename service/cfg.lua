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
local db_auto_upload = false

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
		DATA_UPLOAD = false,
		EVENT_UPLOAD = 99,
		PKG_HOST_URL = "ioe.symgrid.com",
		CNF_HOST_URL = "ioe.symgrid.com",
		--CFG_AUTO_UPLOAD = true,
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

local on_cfg_crash_sh = [[
CFG_JSON=%s
BACKUP_DIR=./__crash_backup
BACKUP_TIME="%s"
rm -rf $BACKUP_DIR
mkdir $BACKUP_DIR
cp ./logs/freeioe.log $BACKUP_DIR/
cp ./logs/freeioe_sys.log $BACKUP_DIR/
mv $CFG_JSON $BACKUP_DIR/
mv $CFG_JSON.md5 $BACKUP_DIR/
echo $BACKUP_TIME > $BACKUP_DIR/backup_time
touch $CFG_JSON.crash
sync
]]

local function on_cfg_failure()
	local sh_file = "/tmp/on_cfg_crash.sh"
	local f, err = io.open(sh_file, "w+")
	if f then
		--local content = string.format(on_cfg_crash_sh, db_file, os.date("%F %T"))
		local content = string.format(on_cfg_crash_sh, db_file, os.date("%Y-%m-%d %H:%M:%S"))
		f:write(content)
		f:close()
		os.execute('sh '..sh_file)
		log.info("::CFG:: Finished crash backup")
	else
		log.error("::CFG:: Cannot create crash backup script file. ", err)
	end
	skynet.sleep(100)
	skynet.abort()
end


local function load_cfg(path)
	log.info("::CFG:: Loading configuration...")
	local file, err = io.open(path, "r")
	if not file then
		dc.set("CLOUD", cfg_defaults())
		dc.set("APPS", {})
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
			on_cfg_failure()
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
	dc.set("CLOUD", db.cloud or {})
	dc.set("APPS", db.apps or {})

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

local function save_cfg_cloud(content, content_md5sum, rest)
	assert(content, content_md5sum)
	if not rest then
		return nil, "Restful api missing"
	end

	log.info("::CFG:: Upload cloud config start")

	local id = dc.wait("CLOUD", "ID")
	local url = "/conf_center/upload_device_conf"
	local params = {
		sn = id,
		timestamp = db_modification,
		data = content,
		md5 = content_md5sum,
	}
	local status, body = rest:post(url, params)
	if not status or status ~= 200 then
		log.warning("::CFG:: Saving cloud config failed", status or -1)
		return nil, "Saving cloud configuration failed!"
	else
		log.info("::CFG:: Upload cloud config done!")
		return true
	end
end

local function load_cfg_cloud(cfg_id, rest)
	assert(cfg_id)
	if not rest then
		return nil, "Restful api missing"
	end

	log.info("::CFG:: Download cloud config start")

	local id = dc.wait("CLOUD", "ID")
	local status, body = rest:get("/conf_center/device_conf_data", nil, {sn=id, name=cfg_id})
	if not status or status ~= 200 then
		log.warning("::CFG:: Get cloud config failed", status or -1, body)
		return nil, "Failed to download device configuration "..cfg_id
	end
	local new_cfg = cjson.decode(body)

	local content = new_cfg.data
	local md5sum = new_cfg.md5

	local sum = md5.sumhexa(content)
	if sum ~= md5sum then
		log.warning("::CFG:: MD5 Checksum error", sum, md5sum)
		return nil, "The downloaded configuration hasing is incorrect!"
	end

	local r, err = save_cfg(db_file, str, sum)
	if not r  then
		log.warning("::CFG:: Saving configurtaion failed", err)
		return nil, "Saving configuration failed!"
	end

	log.notice("::CFG:: Download cloud config finished. FreeIOE reboot in five seconds!!")
	skynet.timeout(500, function()
		-- Quit skynet
		skynet.abort()
	end)
	return true
end

function command.SAVE(opt_path)
	local str, sum = get_cfg_str()
	if sum ~= md5sum then
		local r, err = save_cfg(opt_path or db_file, str, sum)
		if r then
			md5sum = sum
		end

		os.execute('sync')

		if db_auto_upload then
			save_cfg_cloud(str, sum, db_restful)
		end
	end
end

function command.CLEAR()
	db = {}
end

function command.DOWNLOAD(id, host)
	local rest = host and restful:new(host) or db_restful
	return load_cfg_cloud(id, rest)
end

function command.UPLOAD(host)
	local rest = host and restful:new(host) or db_restful
	local str, sum = get_cfg_str()
	return save_cfg_cloud(str, sum, rest)
end

local function init_restful()
	db_auto_upload = dc.get("CLOUD", "CFG_AUTO_UPLOAD")
	if db_auto_upload then
		log.info("::CFG:: System configuration upload enabled!", host)
	end

	local host = dc.get("CLOUD", "CNF_HOST_URL")
	db_restful = restful:new(host)
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

	skynet.fork(function()
		while true do
			command.SAVE()
			skynet.sleep(500)
		end
	end)
end)
