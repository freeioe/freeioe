local skynet = require 'skynet'
local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local pkg_api = require 'utils.pkg_api'
local ioe = require 'ioe'

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
		assert(post.inst and string.len(post.inst) >= 3)
		assert(post.app and string.len(post.app) >= 3)
		assert(post.app_file and type(post.app_file) == 'table')

		local app_file = post.app_file
		local ct = app_file['content-type']
		if ct ~= 'application/zip' and ct ~= 'application/x-zip-compressed' then
			return ngx.print(_('Application package must be zip file'))
		end
		--print(string.len(app_file.contents), app_file.size)
		local path = pkg_api.generate_tmp_path(post.inst, post.app, 'latest', 'zip')
		local f, err = io.open(path, 'w+')
		if not f then
			return err
		end
		f:write(app_file.contents)
		f:close()

		local id = "from_web"
		local args = {
			file = path,
			name = post.app,
			inst = post.inst,
			version = 'latest',
			from_web = true,
			conf = {}
		}

		local r, err = skynet.call(".upgrader", "lua", "install_local_app", id, args)
		if r then
			ngx.print('Application installation is done!')
		else
			ngx.print('Application installation failed', err)
		end
	end,
}
