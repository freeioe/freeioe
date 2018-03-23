local skynet = require 'skynet'
local dc = require 'skynet.datacenter'
local cjson = require 'cjson.safe'

local pack_target_path = "/tmp/iot/"

local function path_join(...)
	return table.concat({...}, '/')
end

local function get_app_path(app, ...)
	return path_join("./iot/apps", app, ...)
end

local function pack_app(inst, version)
	local app = dc.get("APPS", inst)

	local target_file = inst.."_v"..version..".tar.gz"
	local target_file_escape = string.gsub(target_file, " ", "__")
	os.execute("mkdir -p "..pack_target_path)
	local cmd = "tar -cvzf "..pack_target_path..target_file_escape.." "..string.gsub(get_app_path(inst, "*"), " ", "\\ ")
	local r, status, code = os.execute(cmd)
	if not r then
		return nil, "failed to pack application"..inst
	end
	return target_file_escape
end

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local inst = post.app
		local version = post.version or 0
		assert(inst and version)
		local r, err = pack_app(inst, version)

		if r then
			ngx.header.content_type = "application/json; charset=utf-8"
			ngx.print(cjson.encode({
				result = true,
				message = "/assets/tmp/"..r
			}))
		else
			ngx.header.content_type = "application/json; charset=utf-8"
			ngx.print(cjson.encode({
				result = false,
				message = "Failed to pack application. Error: "..err
			}))
		end
	end,
}
