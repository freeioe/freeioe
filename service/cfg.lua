local skynet = require "skynet.manager"
local dc = require "skynet.datacenter"
local cjson = require "cjson.safe"
local md5 = require "md5"

local db_file = "cfg.json"
local db = {}

local command = {}

function command.GET(key)
	return db[key]
end

function command.SET(key, value)
	local last = db[key]
	db[key] = value
	return last
end

local function save_cfg(cfg, path)
	skynet.error("::CFG:: Saving configuration...")
	local file, err = io.open(path, "w+")
	if not file then
		return nil, err
	end

	file:write(cjson.encode(cfg))
	file:close()
end

function command.SAVE(opt_path)
	return save_cfg(db, opt_path or db_file)
end

function command.CLEAR()
	db = {}
end

local function load_conf(path)
	skynet.error("::CFG:: Loading configuration...")
	local file, err = io.open(path, "r")
	if not file then
		return nil, err
	end

	local str = file:read("*a")
	file:close()
	db = cjson.decode(str) or {}
end

local function set_defaults()
	local dc = require 'skynet.datacenter'

	dc.set("CLOUD", "ID", os.getenv("SYS_ID") or "IDIDIDIDID")
	dc.set("CLOUD", "HOST", "symid.com")
	dc.set("CLOUD", "PORT", 1883)
	dc.set("CLOUD", "TIMEOUT", 300)

	dc.set("CLOUD", "PKG_HOST_URL", "symid.com")
end

skynet.start(function()
	set_defaults()
	load_conf(db_file)
	dc.set("CLOUD", db.cloud)
	dc.set("APPS", db.apps)

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
		local md5sum = nil
		while true do
			local cfg = {}
			cfg.cloud = dc.get("CLOUD")
			cfg.apps = dc.get("APPS")
			local str = cjson.encode(cfg)
			local sum = md5.sumhexa(str)
			if sum ~= md5sum then
				--print(sum, md5sum)
				md5sum = sum
				save_cfg(cfg, db_file)
			end
			skynet.sleep(50)
		end
	end)
end)
