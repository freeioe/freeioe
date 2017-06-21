local skynet = require "skynet.manager"
local cjson = require "cjson.safe"

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

function command.SAVE(opt_path)
	skynet.error("::CFG:: Saving configuration...")
	local path = opt_path or db_file
	local file, err = io.open(path, "w+")
	if not file then
		return nil, err
	end

	file:write(cjson.encode(db))
	file:close()
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

skynet.start(function()
	load_conf(db_file)

	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	skynet.register "CFG"
end)
