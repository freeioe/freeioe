local skynet = require "skynet.manager"
local dc = require "skynet.datacenter"
local queue = require "skynet.queue"
local cjson = require "cjson.safe"
local md5 = require "md5"
local lfs = require 'lfs'
local restful = require 'http.restful'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'
local ioe = require 'ioe'

local db_file = "cfg.json"
local md5sum = ""
local db_modification = 0
local db_restful = nil
local db_failure = false

local lock = nil -- Critical Section
local command = {}

function command.GET(app, ...)
	return dc.get('APPS', app, ...)
end

function command.SET(app, ...)
	return dc.set('APPS', app, ...)
end

local function get_cfg_str()
	local cfg = {}
	cfg.cloud = dc.get("CLOUD")
	cfg.apps = dc.get("APPS")
	cfg.sys = dc.get("SYS")
	local str = cjson.encode(cfg)
	return str, md5.sumhexa(str)	
end

local function sys_defaults()
	local ioe_sn = sysinfo.ioe_sn()
	return {
		ID = ioe_sn,
		PKG_HOST_URL = "ioe.thingsroot.com",
		CNF_HOST_URL = "ioe.thingsroot.com",
		--CFG_AUTO_UPLOAD = true,
	}
end

local function cloud_defaults()
	return {
		HOST = "ioe.thingsroot.com",
		PORT = 1883,
		KEEPALIVE = 60,
		DATA_UPLOAD = false,
		EVENT_UPLOAD = 99,
		SECRET = "ZGV2aWNlIGlkCg==",
	}
end

local function set_sys_defaults(data)
	local data = data or {}
	local defaults = sys_defaults()

	--- Fix hacks
	if string.match(data.PKG_HOST_URL or '', 'cloud.thingsroot.com') then
		data.PKG_HOST_URL = nil
	end
	if string.match(data.CNF_HOST_URL or '', 'cloud.thingsroot.com') then
		data.CNF_HOST_URL = nil
	end

	for k,v in pairs(defaults) do
		data[k] = data[k] or v
	end
	if defaults.ID ~= sysinfo.unknown_ioe_sn then
		data.ID = defaults.ID
	end
	return data
end

local function set_cloud_defaults(data)
	local data = data or {}
	local defaults = cloud_defaults()
	for k,v in pairs(defaults) do
		data[k] = data[k] or v
	end
	--- symgrid.com domain hacks
	if string.match(data.HOST, 'symgrid.com') then
		data.HOST = defaults.HOST
	end
	if string.match(data.HOST, 'cloud.thingsroot.com') then
		data.HOST = defaults.HOST
	end

	--- export host to /tmp/sysinfo/cloud
	os.execute('mkdir -p /tmp/sysinfo')
	os.execute('echo "'..data.HOST..'" > /tmp/sysinfo/cloud')
	return data
end

local function backup_cfg(path)
	os.execute("cp "..path.." "..path..".backup")
	os.execute("cp "..path..".md5 "..path..".md5.backup")
	os.execute("sync")
end

local on_cfg_crash_sh = [[
CFG_JSON=%s
BACKUP_DIR=./__crash_backup
BACKUP_TIME="%s"

rm -rf ${BACKUP_DIR}
mkdir ${BACKUP_DIR}

cp ./logs/freeioe.log $BACKUP_DIR/
cp ./logs/freeioe_sys.log $BACKUP_DIR/
mv ${CFG_JSON} ${BACKUP_DIR}/
mv ${CFG_JSON}.md5 ${BACKUP_DIR}/
echo ${BACKUP_TIME} > ${BACKUP_DIR}/backup_time
touch ${CFG_JSON}.crash

if [ -f ${CFG_JSON}.backup ]
then
	mv ${CFG_JSON}.backup ${CFG_JSON}
	mv ${CFG_JSON}.md5.backup ${CFG_JSON}.md5
fi
sync
]]

local function on_cfg_failure()
	db_failure = true
	local sh_file = "/tmp/on_cfg_crash.sh"
	local f, err = io.open(sh_file, "w+")
	if f then
		--local content = string.format(on_cfg_crash_sh, db_file, os.date("%F %T"))
		local content = string.format(on_cfg_crash_sh, db_file, os.date("%Y-%m-%d %H:%M:%S"))
		f:write(content)
		f:close()
		os.execute('sh '..sh_file)
		log.info("::CFG:: Crash backup script finished")
	else
		log.error("::CFG:: Failed to create crash backup script, "..err)
	end
	skynet.sleep(100)
	skynet.abort()
end

local function load_cfg(path)
	log.info("::CFG:: Loading configuration...")
	local file, err = io.open(path, "r")
	if not file then
		dc.set("SYS", sys_defaults())
		dc.set("CLOUD", cloud_defaults())
		dc.set("APPS", {})
		return nil, err
	end

	db_modification = tonumber(lfs.attributes(path, 'modification'))
	--print(db_modification, os.time())

	local str = file:read("*a")
	file:close()

	--- Check the configuration md5
	local sum = md5.sumhexa(str)
	local mfile = io.open(path..".md5", "r")
	if mfile then
		local md5s = mfile:read("*l")
		mfile:close()
		if md5s ~= sum then
			log.error("::CFG:: Configuration file checksum error.", md5s, sum)
			log.error("::CFG:: FreeIOE is aborting, please correct this error manually!")
			on_cfg_failure()
		end
	else
		log.warning("::CFG:: Configuration checksum file is missing, create it")
		local mfile, merr = io.open(path..".md5", "w+")
		if mfile then
			mfile:write(sum)
			mfile:close()
		else
			log.warning("::CFG:: Failed to open checksum file for writing.", merr)
		end
	end

	local db = cjson.decode(str) or {}

	--- The eariler version of FreeIOE put the ID/CLOUD_ID/USING_BETA in cloud sub-node
	if not db.sys and db.cloud then
		db.sys = {}
		db.sys.ID = db.cloud.ID
		db.cloud.ID = db.cloud.CLOUD_ID
		db.cloud.CLOUD_ID = nil

		db.sys.USING_BETA = db.cloud.USING_BETA
		db.cloud.USING_BETA = nil
	end

	--- Load the cloud/sys defaults
	db.cloud = set_cloud_defaults(db.cloud)
	db.sys = set_sys_defaults(db.sys)

	--- Upload value to datacenter
	dc.set("CLOUD", db.cloud or {})
	dc.set("SYS", db.sys or {})
	dc.set("APPS", db.apps or {})

	local _, csum = get_cfg_str()
	md5sum = csum or sum

	backup_cfg(path)
end

local function save_cfg(path, content, content_md5sum)
	log.info("::CFG:: Saving configuration...")
	if path == db_file then
		backup_cfg(path)
	end

	local file, err = io.open(path, "w+")
	if not file then
		return nil, err
	end

	local mfile, merr = io.open(path..".md5", "w+")
	if not mfile then
		return nil, merr
	end
	db_modification = os.time()

	file:write(content)
	file:close()

	mfile:write(content_md5sum)
	mfile:close()

	os.execute("sync")

	return true
end

local function save_cfg_cloud(content, content_md5sum, rest)
	assert(content, content_md5sum)
	if not rest then
		return nil, "Restful api missing, cannot upload configuration to cloud"
	end

	log.info("::CFG:: Start to upload configuration to cloud")

	local id = dc.get("CLOUD", "ID") or dc.wait("SYS", "ID")
	local url = "/conf_center/upload_device_conf"
	local params = {
		sn = id,
		timestamp = db_modification,
		data = content,
		md5 = content_md5sum,
	}
	local status, body = rest:post(url, params)
	if not status or status ~= 200 then
		log.warning("::CFG:: Upload configuration failed. Status:", status or -1, body)
		return nil, "Upload configuration failed!"
	else
		log.info("::CFG:: Upload configuration done!")
		return true
	end
end

local function load_cfg_cloud(cfg_id, rest)
	assert(cfg_id)
	if not rest then
		return nil, "Restful api missing, cannot download configruation from cloud"
	end

	log.info("::CFG:: Start to download configuration from cloud")

	local id = dc.get("CLOUD", "ID") or dc.wait("SYS", "ID")
	local status, body = rest:get("/conf_center/device_conf_data", nil, {sn=id, name=cfg_id})
	if not status or status ~= 200 then
		log.warning("::CFG:: Download configuration failed. Status:", status or -1, body)
		return nil, "Failed to download configuration, id:"..cfg_id
	end
	local new_cfg = cjson.decode(body) or {}

	local new_content = new_cfg.data
	local new_md5sum = new_cfg.md5

	local sum = md5.sumhexa(new_content)
	if sum ~= new_md5sum then
		log.warning("::CFG:: MD5 Checksum failed.", sum, new_md5sum)
		return nil, "The fetched configuration checksum incorrect!"
	end

	local r, err = save_cfg(db_file, new_content, new_md5sum)
	if not r  then
		log.warning("::CFG:: Saving configurtaion failed.", err)
		return nil, "Saving configuration failed!"
	end

	log.notice("::CFG:: Download configuration finished. FreeIOE is reloading!!")
	ioe.abort()

	return true
end

function command.SAVE(opt_path)
	if db_failure then
		return nil, "Configuration is failure state!"
	end

	local str, sum = get_cfg_str()
	if sum ~= md5sum then
		local r, err = save_cfg(opt_path or db_file, str, sum)
		if r then
			md5sum = sum
		else
			return nil, err
		end

		local cfg_upload = dc.get("SYS", "CFG_AUTO_UPLOAD")
		if cfg_upload then
			return save_cfg_cloud(str, sum, db_restful)
		else
			return true
		end
	end
end

--[[
function command.CLEAR()
	db = {}
end
]]--

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
	local cfg_upload = dc.get("SYS", "CFG_AUTO_UPLOAD")
	local cfg_host = dc.get("SYS", "CNF_HOST_URL")

	if cfg_upload and cfg_host then
		log.info("::CFG:: Configuration cloud upload enabled! Server:", cfg_host)
		db_restful = restful:new(cfg_host)
	end
end

skynet.start(function()
	lock = queue()
	load_cfg(db_file)
	init_restful()

	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			lock(function(...)
				skynet.ret(skynet.pack(f(...)))
			end, ...)
		else
			error(string.format("Unknown command %s from session %s-%s", tostring(cmd), tostring(session), tostring(address)))
		end
	end)
	skynet.register ".cfg"

	skynet.fork(function()
		while true do
			lock(function()
				command.SAVE()
			end)
			skynet.sleep(500)
		end
	end)
end)
