local skynet = require "skynet.manager"
local dc = require "skynet.datacenter"
local queue = require "skynet.queue"

local cjson = require "cjson.safe"
local md5 = require "md5"
local lfs = require 'lfs'
local inifile = require 'inifile'

local sysinfo = require 'utils.sysinfo'
local disk = require 'utils.disk'
local pkg_file = require 'pkg.file'
local ioe = require 'ioe'

local log = require 'utils.logger'.new('CFG')

local def_file = '/etc/freeioe.conf'
local def_conf = {}
local db_file = "cfg.json"
local md5sum = ""
local db_modification = 0
local db_failure = false

local lock = nil -- Critical Section
local command = {}
local cfg_lock = nil

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

--- Order or reading pre-defaults
-- read /etc/freeioe.conf
-- get enviorment from system
-- hardcode with ioe.thingsroot.com and pkg ver 1
local function load_defaults()
	if lfs.attributes(def_file, 'mode') then
		local conf = inifile.parse(def_file)
		def_conf = conf['freeioe']
	end

	--- loading environments

	local env_pkg_url = os.getenv('IOE_PKG_URL')
	if env_pkg_url then
		def_conf.IOE_PKG_URL = env_pkg_url
	end

	local env_host = os.getenv('IOE_CLOUD_HOST')
	if env_pkg_url then
		def_conf.IOE_PKG_URL = env_host
	end

	local env_ver = os.getenv('IOE_PKG_VERSION')
	if env_ver then
		def_conf.IOE_PKG_VERSION = env_ver 
	end
end

local function _sys_defaults()
	local ioe_sn = sysinfo.ioe_sn()
	local url_def = def_conf.IOE_PKG_URL or 'ioe.thingsroot.com'
	local pkg_ver = def_conf.IOE_PKG_VERSION or 1
	return {
		ID = ioe_sn,
		PKG_VER = pkg_ver,
		PKG_HOST_URL = url_def,
		CNF_HOST_URL = url_def,
		WORK_MODE = 0, --
	}
end

local function _cloud_defaults()
	local host_def = def_conf.IOE_CLOUD_HOST or 'ioe.thingsroot.com'
	return {
		HOST = host_def,
		PORT = 1883,
		KEEPALIVE = 60,
		DATA_UPLOAD = false,
		DATA_CACHE = true,
		EVENT_UPLOAD = 99,
		SECRET = "ZGV2aWNlIGlkCg==",
	}
end

local function set_sys_defaults(data)
	local data = data or {}
	local defaults = _sys_defaults()

	for k,v in pairs(defaults) do
		data[k] = data[k] or v
	end

	if defaults.ID ~= sysinfo.unknown_ioe_sn then
		data.ID = defaults.ID
	end
	return data
end

local function data_cache_compatitable()
	local ddir = sysinfo.data_dir()
	if ddir == '/tmp' then
		--- Allow in developer mode
		if os.getenv("IOE_DEVELOPER_MODE") then
			return true
		end
		local err = 'Data cache not allowed on /tmp'
		log.warning(err)
		return nil, err
	end
	if not lfs.attributes(ddir, 'mode') then
		local err = 'Data cache not exists'
		log.warning(err)
		return nil, err
	end

	local dir, err = disk.df(ddir)
	if not dir or not dir.total then
		log.warning("Cannot access data directory", ddir, err)
		return nil, err
	end

	--- total unit is 1K-block
	if dir.total < 256 * 1024 then
		log.warning("Data cache directory is too small!", ddir, dir.total)
		return nil, "Data dir is too small"
	else
		log.notice("Data cache directory info", ddir, dir.total)
	end

	return true
end

local function set_cloud_defaults(data)
	local data = data or {}
	local defaults = _cloud_defaults()
	for k,v in pairs(defaults) do
		data[k] = data[k] or v
	end

	if not data_cache_compatitable() then
		log.info("Data cache not allowed in currect device")
		data.DATA_CACHE = false
	end

	--- export host to /tmp/sysinfo/cloud
	os.execute('mkdir -p /tmp/sysinfo')
	os.execute('echo "'..data.HOST..'" > /tmp/sysinfo/cloud')
	return data
end

local function backup_cfg(path)
	os.execute("cp "..path.." "..path..".backup")
	os.execute("cp "..path..".md5 "..path..".md5.backup")
	os.execute("sync &")
end

local on_cfg_crash_sh = [[
CFG_JSON=%s
BACKUP_DIR=./__crash_backup
BACKUP_TIME="%s"

rm -rf ${BACKUP_DIR}
mkdir ${BACKUP_DIR}

cp ./logs/freeioe.log $BACKUP_DIR/
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
		log.info("Crash backup script finished")
	else
		log.error("Failed to create crash backup script, "..err)
	end
	skynet.sleep(100)
	skynet.abort()
end

local function load_cfg(path)
	log.info("Loading configuration...")
	local file, err = io.open(path, "r")
	if not file then
		dc.set("SYS", set_sys_defaults())
		dc.set("CLOUD", set_cloud_defaults())
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
			log.error("Configuration file checksum error.", md5s, sum)
			log.error("FreeIOE is aborting, please correct this error manually!")
			on_cfg_failure()
		end
	else
		log.warning("Configuration checksum file is missing, create it")
		local mfile, merr = io.open(path..".md5", "w+")
		if mfile then
			mfile:write(sum)
			mfile:close()
		else
			log.warning("Failed to open checksum file for writing.", merr)
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

	-- The config is ok, thus backup it
	backup_cfg(path)

	return true
end

local function save_cfg(path, content, content_md5sum)
	if cfg_lock then
		log.info("Saving configuration failed, as it is locked")
		return
	end

	log.info("Saving configuration...")
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

local function save_cfg_cloud(content, content_md5sum, comment)
	assert(content, content_md5sum)

	log.info("Start to upload configuration to cloud")

	local ret, err = pkg_file.upload('cfg.json', content, content_md5sum, os.time(), comment)

	if not ret then
		log.warning("Upload configuration failed. Error:", err)
		return nil, err
	else
		log.info("Upload configuration done!")
		return true
	end
end

local function load_cfg_cloud(cfg_id)
	assert(cfg_id)
	log.info("Start to download configuration from cloud", cfg_id)

	local data, md5sum = pkg_file.download(cfg_id)
	if not data then
		log.warning("Download configuration failed. Error:", md5)
		return nil, "Failed to download configuration, id:"..cfg_id
	end

	local sum = md5.sumhexa(data)
	if sum ~= md5sum then
		log.warning("MD5 Checksum failed.", sum, md5sum)
		return nil, "The fetched configuration checksum incorrect!"
	end

	local cfg_data, err = cjson.decode(data)
	if not cfg_data then
		log.warning("Loading cfg json failed.", err)
		return nil, err
	end

	--- Make sure we will not over-write the important things
	cfg_data.sys.ID = ioe.id()
	cfg_data.sys.PKG_VER = ioe.pkg_ver()
	cfg_data.sys.PKG_HOST_URL = ioe.pkg_host_url()
	cfg_data.sys.CNF_HOST_URL = ioe.cnf_host_url()	
	cfg_data.cloud.HOST = ioe.cloud_host()
	cfg_data.cloud.PORT = ioe.cloud_port()
	cfg_data.cloud.SECRET = ioe.cloud_secret()

	local cfg_str, err = cjson.encode(cfg_data)
	if not cfg_str then
		log.warning("Encoding cfg json failed.", err)
		return nil, err
	end
	local cfg_md5 = md5.sumhexa(cfg_str)

	local r, err = save_cfg(db_file, cfg_str, cfg_md5)
	if not r  then
		log.warning("Saving configurtaion failed.", err)
		return nil, "Saving configuration failed!"
	end

	cfg_lock = true --lock it and wait for abort

	log.notice("Download configuration finished. FreeIOE is reloading!!")
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
	end

	return true
end

--[[
function command.CLEAR()
	db = {}
end
]]--

function command.DOWNLOAD(id)
	return load_cfg_cloud(id)
end

function command.UPLOAD(comment)
	local str, sum = get_cfg_str()
	return save_cfg_cloud(str, sum, comment)
end

skynet.start(function()
	lock = queue()
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
	skynet.sleep(10)

	--- Load defaults
	load_defaults()

	load_cfg(db_file)
	log.info("BETA:", dc.get('SYS', 'USING_BETA'), 'MODE:', dc.get('SYS', 'WORK_MODE'))

	skynet.fork(function()
		while true do
			lock(function()
				command.SAVE()
			end)
			skynet.sleep(500)
		end
	end)

	skynet.register ".cfg"
end)
