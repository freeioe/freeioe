local skynet = require 'skynet.manager'
local snax = require 'skynet.snax'
--local queue = require 'skynet.queue'
local lockable_queue = require 'skynet.lockable_queue'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'
local lfs = require 'lfs'
local datacenter = require 'skynet.datacenter'
local pkg_api = require 'utils.pkg_api'
local ioe = require 'ioe'

local sys_lock = nil
local app_lock = nil
--local task_lock = nil
local tasks = {}
local aborting = false

local command = {}

local get_target_folder = pkg_api.get_app_folder
local parse_version_string = pkg_api.parse_version_string
local get_app_version = pkg_api.get_app_version

local function get_ioe_dir()
	return os.getenv('IOE_DIR') or lfs.currentdir().."/.."
end

local reserved_list = {
	"ioe", "ioe_frpc", "ioe_symlink",
	"UBUS", "CLOUD", "AppMgr", "CFG", "LWF", "EXT",
	"RunBatch", "BUFFER", "UPGRADER"
}

local function is_inst_name_reserved(inst)
	for _, v in ipairs(reserved_list) do
		if v == inst then
			return true
		end
	end
end

local function action_result(channel, id, result, info, ...)
	local info = info or (result and 'Done [UNKNOWN]' or 'Error! [UNKNOWN]')
	if result then
		log.info("::UPGRADER:: "..info, ...)
	else
		log.error("::UPGRADER:: "..info, ...)
	end

	if id and id ~= 'from_web' then
		local cloud = snax.queryservice('cloud')
		cloud.post.action_result(channel, id, result, info, ...)
	end
	return result, ...
end

local function fire_warning_event(info, data)
	local appmgr = snax.queryservice("appmgr")
	local event = require 'app.event'
	appmgr.post.fire_event('ioe', ioe.id(), event.LEVEL_WARNING, event.EVENT_SYS, info, data)
end

--[[
local function xpcall_ret(channel, id, ok, ...)
	if ok then
		return action_result(channel, id, ...)
	end
	return action_result(channel, id, false, ...)
end

local function action_exec(channel, func)
	local channel = channel
	local func = func
	return function(id, args)
		return xpcall_ret(channel, id, xpcall(func, debug.traceback, id, args))
	end
end
]]--

--[[
local function create_task(lock, task_func)
	local spawn_co = {}
	skynet.fork(function()
		-- Make sure we locked the queue
		skynet.wakeup(spawn_co)
		task_lock(task_func)
	end)
	skynet.wait(spawn_co)
	return true
end
]]--

local function create_task(func, task_name, ...)
	if aborting then
		return false, "System is aborting"
	end

	skynet.fork(function(task_name, ...)
		local co = coroutine.running()
		tasks[co] = {
			name = task_name
		}
		local r, err = func(...)
		tasks[co] = nil

		if not r then
			log.error("::UPGRADER:: Task executed failed.", task_name, err)
		end
	end, task_name, ...)

	return true, task_name.. " started"
end

local function gen_app_sn(inst_name)
	local cloud = snax.queryservice('cloud')
	return cloud.req.gen_sn(inst_name)
end

local function create_download(channel)
	return function(inst_name, app_name, version, success_cb, ext)
		local down = pkg_api.create_download_func(inst_name, app_name, version, ext or '.zip')
		return down(success_cb)
	end
end

local create_app_download = create_download('app')
local create_sys_download = create_download('sys')

local function map_app_action(func_name, lock)
	local func = command[func_name]
	assert(func)
	command[func_name] = function(id, args)
		return create_task(function()
			return action_result('app', id, app_lock(func, lock, id, args))
		end, 'Application Action '..func_name)
	end
end

local function map_sys_action(func_name, lock)
	local func = command[func_name]
	assert(func)
	command[func_name] = function(id, args)
		return create_task(function()
			return action_result('sys', id, sys_lock(func, lock, id, args))
		end, 'System Action '..func_name)
	end
end

function command.upgrade_app(id, args)
	local inst_name = args.inst
	local version, beta, editor = parse_version_string(args.version)
	if beta and not ioe.beta() then
		return false, "Device is not in beta mode! Cannot install beta version"
	end
	if not pkg_api.valid_inst(inst_name) then
		return false, "Application instance name invalid!!"
	end

	local app = datacenter.get("APPS", inst_name)
	if not app then
		return false, "There is no app for instance name "..inst_name
	end

	local name = args.fork and args.name or app.name
	if args.name and args.name ~= name then
		return false, "Cannot upgrade application as name is different, installed "..app.name.." wanted "..args.name
	end
	local sn = args.sn or app.sn
	local conf = args.conf or app.conf
	local auto = args.auto

	local download_version = editor and version..".editor" or version
	return create_app_download(inst_name, name, download_version, function(path)
		log.notice("::UPGRADER:: Download application finished", name)
		local appmgr = snax.queryservice("appmgr")
		local r, err = appmgr.req.stop(inst_name, "Upgrade Application")
		if not r then
			return false, "Failed to stop App. Error: "..err
		end

		local target_folder = get_target_folder(inst_name)
		os.execute("unzip -oq "..path.." -d "..target_folder)
		os.execute("rm -rf "..path)

		if not version or version == 'latest' then
			version = get_app_version(inst_name)
		end
		datacenter.set("APPS", inst_name, {name=name, version=version, sn=sn, conf=conf, auto=auto})
		if editor then
			datacenter.set("APPS", inst_name, "islocal", 1)
		end

		local r, err = appmgr.req.start(inst_name, conf)
		if r then
			--- Post to appmgr for instance added
			appmgr.post.app_event('upgrade', inst_name)

			return true, "Application upgradation is done!"
		else
			-- Upgrade will not remove app folder
			--datacenter.set("APPS", inst_name, nil)
			--os.execute("rm -rf "..target_folder)
			return false, "Failed to start App. Error: "..err
		end
	end)
end

function command.install_app(id, args)
	local name = args.name
	local inst_name = args.inst
	local from_web = args.from_web
	local version, beta, editor = parse_version_string(args.version)
	if beta and not ioe.beta() then
		return false, "Device is not in beta mode! Cannot install beta version"
	end
	if not pkg_api.valid_inst(inst_name) then
		return false, "Application instance name invalid!!"
	end

	local sn = args.sn or gen_app_sn(inst_name)
	local conf = args.conf or {}
	if not from_web and is_inst_name_reserved(inst_name) then
		local err = "Application instance name is reserved"
		return false, "Failed to install App. Error: "..err
	end
	if datacenter.get("APPS", inst_name) and not args.force then
		local err = "Application already installed"
		return false, "Failed to install App. Error: "..err
	end

	-- Reserve app instance name
	datacenter.set("APPS", inst_name, {name=name, version=version, sn=sn, conf=conf, downloading=true})

	local download_version = editor and version..".editor" or version
	local r, err = create_app_download(inst_name, name, download_version, function(info)
		log.notice("::UPGRADER:: Download application finished", name)
		local target_folder = get_target_folder(inst_name)
		lfs.mkdir(target_folder)
		os.execute("unzip -oq "..info.." -d "..target_folder)
		os.execute("rm -rf "..info)

		if not version or version == 'latest' then
			version = get_app_version(inst_name)
		end
		datacenter.set("APPS", inst_name, {name=name, version=version, sn=sn, conf=conf})
		if editor then
			datacenter.set("APPS", inst_name, "islocal", 1)
		end

		local appmgr = snax.queryservice("appmgr")
		local r, err = appmgr.req.start(inst_name, conf)
		if r then
			--- Post to appmgr for instance added
			appmgr.post.app_event('install', inst_name)

			return true, "Application installtion is done"
		else
			-- Keep the application there.
			-- datacenter.set("APPS", inst_name, nil)
			-- os.execute("rm -rf "..target_folder)
			--
			datacenter.set("APPS", inst_name, 'auto', 0)

			appmgr.post.app_event('install', inst_name)

			return false, "Failed to start App. Error: "..err
		end
	end)

	return r, err
end

function command.create_app(id, args)
	local name = args.name
	local inst_name = args.inst
	local version = 0

	if not ioe.beta() then
		return false, "Device is not in beta mode! Cannot install beta version"
	end
	if not pkg_api.valid_inst(inst_name) then
		return false, "Application instance name invalid!!"
	end

	local sn = args.sn or gen_app_sn(inst_name)
	local conf = args.conf or {}
	if is_inst_name_reserved(inst_name) then
		local err = "Application instance name is reserved"
		return false, "Failed to install App. Error: "..err
	end
	if datacenter.get("APPS", inst_name) and not args.force then
		local err = "Application already installed"
		return false, "Failed to install App. Error: "..err
	end

	-- Reserve app instance name
	datacenter.set("APPS", inst_name, {name=name, version=version, sn=sn, conf=conf, islocal=1, auto=0})

	local target_folder = get_target_folder(inst_name)
	lfs.mkdir(target_folder)
	local target_folder_escape = string.gsub(target_folder, ' ', '\\ ')
	os.execute('cp ./ioe/doc/app/example_app.lua '..target_folder_escape..'/app.lua')
	os.execute('echo 0 > '..target_folder.."/version")
	os.execute('echo editor >> '..target_folder.."/version")

	--- Post to appmgr for instance added
	local appmgr = snax.queryservice("appmgr")
	appmgr.post.app_event('create', inst_name)

	return true, "Create application is done!"
end

function command.install_local_app(id, args)
	local name = args.name
	local inst_name = args.inst
	local sn = args.sn or gen_app_sn(inst_name)
	local conf = args.conf or {}
	local file_path = args.file

	if not ioe.beta() then
		return nil, "Device is not in beta mode! Cannot install beta version"
	end
	if not pkg_api.valid_inst(inst_name) then
		return false, "Application instance name invalid!!"
	end

	if is_inst_name_reserved(inst_name) then
		return false, "Application instance name is reserved"
	end
	if datacenter.get("APPS", inst_name) and not args.force then
		return nil, "Application already installed"
	end

	-- Reserve app instance name
	datacenter.set("APPS", inst_name, {name=name, version=0, sn=sn, conf=conf, islocal=1, auto=0})
	log.notice("::UPGRADER:: Install local application package", file_path)

	local target_folder = get_target_folder(inst_name)
	os.execute("unzip -oq "..file_path.." -d "..target_folder)
	os.execute("rm -rf "..file_path)

	local version = get_app_version(inst_name)
	datacenter.set("APPS", inst_name, "version", version)
	--datacenter.set("APPS", inst_name, "auto", 1)

	--- Post to appmgr for instance added
	local appmgr = snax.queryservice("appmgr")
	appmgr.post.app_event('create', inst_name)

	--[[
	log.notice("::UPGRADER:: Try to start application", inst_name)
	appmgr.post.app_start(inst_name)
	]]--

	return true, "Install location application done!"
end

function command.rename_app(id, args)
	local inst_name = args.inst
	local new_name = args.new_name
	if not pkg_api.valid_inst(inst_name) or not pkg_api.valid_inst(new_name) then
		return false, "Application instance name invalid!!"
	end
	if is_inst_name_reserved(inst_name) then
		return nil, "Application instance name is reserved"
	end
	if is_inst_name_reserved(new_name) then
		return nil, "Application new name is reserved"
	end
	if datacenter.get("APPS", new_name) and not args.force then
		return nil, "Application new already used"
	end
	local app = datacenter.get("APPS", inst_name)
	if not app then
		return nil, "Application instance not installed"
	end
	local appmgr = snax.queryservice("appmgr")
	appmgr.req.stop(inst_name, "Renaming application")
	app.sn = args.sn or gen_app_sn(new_name)

	local source_folder = get_target_folder(inst_name)
	local target_folder = get_target_folder(new_name)
	os.execute("mv "..source_folder.." "..target_folder)

	datacenter.set("APPS", inst_name, nil)
	datacenter.set("APPS", new_name, app)

	--- rename event will start the application
	appmgr.post.app_event('rename', inst_name, new_name)

	return true, "Rename application is done!"
end

function command.install_missing_app(inst_name)
	skynet.timeout(100, function()
		local info = datacenter.get("APPS", inst_name)
		if not info or info.islocal then
			return
		end
		return command.install_app(nil, {
			inst = inst_name,
			name = info.name,
			version = info.version,
			sn = info.sn,
			conf = info.conf,
			force = true
		})
	end)
	return true, "Install missing application "..inst_name.." done!"
end

function command.uninstall_app(id, args)
	local inst_name = args.inst
	if not pkg_api.valid_inst(inst_name) then
		return false, "Application instance name invalid!!"
	end

	local appmgr = snax.queryservice("appmgr")
	local target_folder = get_target_folder(inst_name)

	local r, err = appmgr.req.stop(inst_name, "Uninstall App")
	if r then
		os.execute("rm -rf "..target_folder)
		datacenter.set("APPS", inst_name, nil)
		appmgr.post.app_event('uninstall', inst_name)
		return true, "Application uninstall is done"
	else
		return false, "Application uninstall failed, Error: "..err
	end
end

function command.list_app()
	return datacenter.get("APPS")
end

function command.pkg_check_update(app, beta)
	local pkg_host = ioe.pkg_host_url()
	local beta = beta and ioe.beta()
	return pkg_api.pkg_check_update(pkg_host, app, beta)
end

function command.pkg_check_version(app, version)
	local pkg_host = ioe.pkg_host_url()
	return pkg_api.pkg_check_version(pkg_host, app, version)
end

function command.pkg_enable_beta()
	local fn = get_ioe_dir()..'/ipt/using_beta'

	if lfs.attributes(fn, 'mode') then
		return true
	end

	local pkg_host = ioe.pkg_host_url()
	local sys_id = ioe.id()

	local r, err = pkg_api.pkg_enable_beta(pkg_host, sys_id)
	if r then
		os.execute('date > '..fn)
	end
	return r, err
end

function command.pkg_user_access(auth_code)
	local pkg_host = ioe.pkg_host_url()
	local sys_id = ioe.id()
	return pkg_api.pkg_user_access(pkg_host, sys_id, auth_code)
end

local function get_core_name(name, platform)
	assert(name, 'Core name is required!')
	local platform = platform or sysinfo.platform()
	if platform then
		--name = platform.."_"..name
		--- FreeIOE not takes the os version before. so using openwrt/arm_cortex-a9_neon_skynet as download core name
		---		now it switched to bin/openwrt/17.01/arm_cortex-a9_neon/skynet
		name = string.format("bin/%s/%s", platform, name)
	end
	return name
end

local function download_upgrade_skynet(id, args, cb)
	--local is_windows = package.config:sub(1,1) == '\\'
	local version, beta = parse_version_string(args.version)
	local kname = get_core_name('skynet', args.platform)

	--- TODO: Check about beta

	return create_sys_download('__SKYNET__', kname, version, cb, ".tar.gz")
end

--[[
local function get_ps_e()
	local r, status, code = os.execute("ps -e > /dev/null")
	if not r then
		return "ps"
	end
	return "ps -e"
end
]]--

local upgrade_sh_str = [[
#!/bin/sh

IOE_DIR=%s
SKYNET_FILE=%s
SKYNET_PATH=%s
FREEIOE_FILE=%s
FREEIOE_PATH=%s

date > $IOE_DIR/ipt/rollback
cp -f $SKYNET_PATH/cfg.json $IOE_DIR/ipt/cfg.json.bak
cp -f $SKYNET_PATH/cfg.json.md5 $IOE_DIR/ipt/cfg.json.md5.bak

cd $IOE_DIR
if [ -f $SKYNET_FILE ]
then
	cd $SKYNET_PATH
	rm ./lualib -rf
	rm ./luaclib -rf
	rm ./service -rf
	rm ./cservice -rf
	tar xzf $SKYNET_FILE

	if [ $? -eq 0 ]
	then
		echo "Skynet upgrade is done!"
	else
		echo "Skynet uncompress error!! Rollback..."
		rm -f $SKYNET_FILE
		sh $IOE_DIR/ipt/rollback.sh
		exit $?
	fi
fi

cd "$IOE_DIR"
if [ -f $FREEIOE_FILE ]
then
	cd $FREEIOE_PATH
	rm ./www -rf
	rm ./lualib -rf
	rm ./snax -rf
	rm ./test -rf
	rm ./service -rf
	rm ./ext -rf
	tar xzf $FREEIOE_FILE

	if [ $? -eq 0 ]
	then
		echo "FreeIOE upgrade is done!"
	else
		echo "FreeIOE uncompress error!! Rollback..."
		rm -f $FREEIOE_FILE
		sh $IOE_DIR/ipt/rollback.sh
		exit $?
	fi
fi

if [ -f $IOE_DIR/ipt/strip_mode ]
then
	rm -f $IOE_DIR/ipt/rollback
	rm -f $IOE_DIR/ipt/upgrade_no_ack

	if [ -f $IOE_DIR/ipt/rollback.sh.new ]
	then
		mv -f $IOE_DIR/ipt/rollback.sh.new $IOE_DIR/ipt/rollback.sh
	fi

	[ -f $SKYNET_FILE ] && rm -f $SKYNET_FILE
	[ -f $FREEIOE_FILE ] && rm -f $FREEIOE_FILE

	exit 0
fi

if [ -f $IOE_DIR/ipt/upgrade_no_ack ]
then
	rm -f $IOE_DIR/ipt/rollback
	rm -f $IOE_DIR/ipt/upgrade_no_ack

	if [ -f $IOE_DIR/ipt/rollback.sh.new ]
	then
		mv -f $IOE_DIR/ipt/rollback.sh.new $IOE_DIR/ipt/rollback.sh
	fi

	if [ -f $SKYNET_FILE ]
	then
		mv -f $SKYNET_FILE $IOE_DIR/ipt/skynet.tar.gz
	fi
	if [ -f $FREEIOE_FILE ]
	then
		mv -f $FREEIOE_FILE $IOE_DIR/ipt/freeioe.tar.gz
	fi
else
	if [ -f $SKYNET_FILE ]
	then
		mv -f $SKYNET_FILE $IOE_DIR/ipt/skynet.tar.gz.new
	fi
	if [ -f $FREEIOE_FILE ]
	then
		mv -f $FREEIOE_FILE $IOE_DIR/ipt/freeioe.tar.gz.new
	fi
fi

sync

]]

local rollback_sh_str = [[
#!/bin/sh

IOE_DIR=%s
SKYNET_PATH=%s
FREEIOE_PATH=%s

if [ -f $IOE_DIR/ipt/skynet.tar.gz ]
then
	cd $IOE_DIR
	cd $SKYNET_PATH
	tar xzf $IOE_DIR/ipt/skynet.tar.gz
fi

if [ -f $IOE_DIR/ipt/freeioe.tar.gz ]
then
	cd $IOE_DIR
	cd $FREEIOE_PATH
	tar xzf $IOE_DIR/ipt/freeioe.tar.gz
fi

if [ -f $IOE_DIR/ipt/cfg.json.bak ]
then
	cp -f $IOE_DIR/ipt/cfg.json.bak $SKYNET_PATH/cfg.json
	cp -f $IOE_DIR/ipt/cfg.json.md5.bak $SKYNET_PATH/cfg.json.md5
fi

sync
]]

local upgrade_ack_sh_str = [[
#!/bin/sh

IOE_DIR=%s

if [ -f $IOE_DIR/ipt/skynet.tar.gz.new ]
then
	mv -f $IOE_DIR/ipt/skynet.tar.gz.new $IOE_DIR/ipt/skynet.tar.gz
fi

if [ -f $IOE_DIR/ipt/freeioe.tar.gz.new ]
then
	mv -f $IOE_DIR/ipt/freeioe.tar.gz.new $IOE_DIR/ipt/freeioe.tar.gz
fi

if [ -f $IOE_DIR/ipt/rollback.sh.new ]
then
	mv -f $IOE_DIR/ipt/rollback.sh.new $IOE_DIR/ipt/rollback.sh
fi

rm -f $IOE_DIR/ipt/rollback

sync

]]

local function write_script(fn, str)
	local f, err = io.open(fn, "w+")
	if not f then
		return nil, err
	end
	f:write(str)
	f:close()
	return true
end

local function start_upgrade_proc(ioe_path, skynet_path)
	assert(ioe_path or skynet_path)
	local ioe_path = ioe_path or '/IamNotExits.unknown'
	local skynet_path = skynet_path or '/IamNotExits.unknown'
	log.warning("::UPGRADER:: Core system upgradation starting....")
	log.trace("::UPGRADER::", ioe_path, skynet_path)
	--local ps_e = get_ps_e()

	local base_dir = get_ioe_dir()

	local str = string.format(rollback_sh_str, base_dir, "skynet", "freeioe")
	local r, err = write_script(base_dir.."/ipt/rollback.sh.new", str)
	if not r then
		return false, err
	end

	local str = string.format(upgrade_ack_sh_str, base_dir)
	local r, err = write_script(base_dir.."/ipt/upgrade_ack.sh", str)
	if not r then
		return false, err
	end

	local str = string.format(upgrade_sh_str, base_dir, skynet_path, "skynet", ioe_path, "freeioe")
	local r, err = write_script(base_dir.."/ipt/upgrade.sh", str)
	if not r then
		return false, err
	end
	write_script(base_dir.."/ipt/upgrade", os.date())

	aborting = true
	ioe.abort()
	log.warning("::UPGRADER:: Core system upgradation done!")
	return true, "System upgradation is done!"
end

function command.upgrade_core(id, args)
	--local is_windows = package.config:sub(1,1) == '\\'

	if args.no_ack then
		local base_dir = get_ioe_dir()
		local r, status, code = os.execute("date > "..base_dir.."/ipt/upgrade_no_ack")
		if not r then
			log.error("::UPGRADER:: Create upgrade_no_ack failed", status, code)
			return false, "Failed to create upgrade_no_ack file!"
		end
	end

	local skynet_args = args.skynet
	--- Upgrade skynet only
	if not args.version or string.lower(args.version) == 'none' then
		return download_upgrade_skynet(id, skynet_args, function(path)
			return start_upgrade_proc(nil, path)
		end)
	end

	local version, beta = parse_version_string(args.version)

	return create_sys_download('__FREEIOE__', 'freeioe', version, function(path)
		local freeioe_path = path
		if skynet_args then
			return download_upgrade_skynet(id, skynet_args, function(path)
				return start_upgrade_proc(freeioe_path, path)
			end)
		else
			return start_upgrade_proc(freeioe_path)
		end
	end, ".tar.gz")
end

local rollback_time = nil
function command.upgrade_core_ack(id, args)
	local base_dir = get_ioe_dir()
	local upgrade_ack_sh = base_dir.."/ipt/upgrade_ack.sh"
	local r, status, code = os.execute("sh "..upgrade_ack_sh)
	if not r then
		return false, "Failed execute ugprade_ack.sh.  "..status.." "..code
	end
	rollback_time = nil
	return true, "System upgradation ACK is done"
end

function command.rollback_time()
	return rollback_time and math.floor(rollback_time - skynet.time()) or nil
end

function command.is_upgrading()
	-- TODO: make a upgrading flag?
	return false
end

function command.list_tasks()
	return tasks
end

function command.system_reboot(id, args)
	aborting = true
	local delay = args.delay or 5
	ioe.abort_prepare()
	skynet.timeout(delay * 100, function()
		os.execute("reboot &")
	end)
	return true, "Device will reboot after "..delay.." seconds"
end

function command.system_quit(id, args)
	aborting = true
	local delay = (args.delay or 5) * 1000
	ioe.abort(delay)
	return true, "FreeIOE will reboot after "..delay.." seconds"
end

local function check_rollback()
	local fn = get_ioe_dir()..'/ipt/rollback'
	if lfs.attributes(fn, 'mode') then
		return true
	end
	return false
end

local function rollback_co()
	log.warning("::UPGRADER:: Rollback will be applied in five minutes")

	local do_rollback = nil
	do_rollback = function()
		local data = { version=sysinfo.version(), skynet_version=sysinfo.skynet_version() }
		fire_warning_event('System will be rollback!', data)
		log.error("::UPGRADER:: System will be rollback!")

		aborting = true
		skynet.sleep(100)
		do_rollback = nil
		ioe.abort()
	end

	rollback_time = skynet.time() + 5 * 60
	skynet.timeout(5 * 60 * 100, function()
		if do_rollback then do_rollback() end
	end)

	while do_rollback do
		skynet.sleep(100)
		if not check_rollback() then do_rollback = nil end
	end
end

-- map action result functions
map_app_action('upgrade_app', false)
map_app_action('install_app', false)
map_app_action('create_app', false)
map_app_action('install_local_app', false)
map_app_action('rename_app', false)
map_app_action('uninstall_app', false)

map_sys_action('upgrade_core', true)
--map_action('upgrade_code_ack', 'sys')
map_sys_action('system_reboot', true)
map_sys_action('system_quit', true)

skynet.start(function()
	sys_lock = lockable_queue()
	app_lock = lockable_queue(sys_lock, false)
	--task_lock = queue()

	lfs.mkdir(get_ioe_dir().."/ipt")

	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.lower(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)

	skynet.register ".upgrader"

	--- For rollback thread
	if check_rollback() then
		skynet.fork(function()
			sys_lock(rollback_co, true)
		end)
		skynet.sleep(20)
	end
end)

