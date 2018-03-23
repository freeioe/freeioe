local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

local function pack_app(inst, version)
	local app = dc.get("APPS", inst)
	-- TODO:zip files
	local r, status, code = os.execute("sh "..upgrade_ack_sh)
	if not r then
		return install_result(id, false, "Failed execute ugprade_ack.sh.  "..status.." "..code)
	end
end

return {
	post = function(self)
		if lwf.auth.user == 'Guest' then
			ngx.print(_('You are not logined!'))
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local inst = post.inst
		local version = post.version
		assert(inst and version)
		local r, err = pack_app(inst, version)

		if r then
			ngx.print('Application creation is done!')
		else
			ngx.print('Application creation failed', err)
		end
	end,
}
