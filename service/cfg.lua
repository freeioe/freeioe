local skynet = require "skynet.manager"
local dc = require "skynet.datacenter"
local cjson = require "cjson.safe"
local md5 = require "md5"
local lfs = require 'lfs'
local restful = require 'restful'

local db_file = "cfg.json"
local md5sum = ""
local db_modification = 0

local command = {}

function command.GET(app, ...)
	return dc.get('APPS', app, ...)
end

function command.SET(...)
	return dc.set('APPS', app, ...)
end

local function load_cfg(path)
	skynet.error("::CFG:: Loading configuration...")
	local file, err = io.open(path, "r")
	if not file then
		return nil, err
	end

	db_modification = tonumber(lfs.attributes(path, 'modification'))
	print(db_modification, os.time())

	local str = file:read("*a")
	file:close()
	local sum = md5.sumhexa(str)
	local mfile, err = io.open(path..".md5", "r")
	if mfile then
		local md5s = mfile:read("*l")
		if md5s ~= sum then
			log.warning("::CFG:: File md5 checksum error", md5s, sum)
		end
	end

	db = cjson.decode(str) or {}

	dc.set("CLOUD", db.cloud)
	dc.set("APPS", db.apps)
end

local function save_cfg(path, content, content_md5sum)
	skynet.error("::CFG:: Saving configuration...")
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

function command.SAVE(opt_path)
	local cfg = {}
	cfg.cloud = dc.get("CLOUD")
	cfg.apps = dc.get("APPS")
	local str = cjson.encode(cfg)
	local sum = md5.sumhexa(str)
	if sum ~= md5sum then
		--print(sum, md5sum)
		local r, err = save_cfg(opt_path or db_file, str, sum)
		if r then
			md5sum = sum
		end
	end
end

function command.CLEAR()
	db = {}
end

local function set_defaults()
	dc.set("CLOUD", "ID", os.getenv("SYS_ID") or "IDIDIDIDID")
	dc.set("CLOUD", "HOST", "symid.com")
	dc.set("CLOUD", "PORT", 1883)
	dc.set("CLOUD", "TIMEOUT", 300)

	dc.set("CLOUD", "PKG_HOST_URL", "symid.com")
	dc.set("CLOUD", "CFG", "URL", "symid.com/device_conf")
	dc.set("CLOUD", "CFG", "ENABLE", 0)
end

skynet.start(function()
	set_defaults()
	load_cfg(db_file)

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
