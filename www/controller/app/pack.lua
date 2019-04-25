local skynet = require 'skynet'
local dc = require 'skynet.datacenter'
local cjson = require 'cjson.safe'
local ioe = require 'ioe'
local afe = require 'utils.app_file_editor'

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		local using_beta = ioe.beta()
		if not using_beta then
			ngx.print(_('FreeIOE device in not in beta mode!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local inst = post.app
		local version = tonumber(post.version)
		assert(inst and string.len(inst) > 0)
		local r, err = afe.post_ops.pack_app(inst, version)

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
