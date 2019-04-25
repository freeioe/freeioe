local ioe = require 'ioe'

local app_file_editor = require 'utils.app_file_editor'
local get_ops = app_file_editor.get_ops
local post_ops = app_file_editor.post_ops

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		end
		local using_beta = ioe.beta()
		if not using_beta then
			return
		end

		local get = ngx.req.get_uri_args()
		local app = get.app
		local operation = get.operation
		local node_id = get.id ~= '/' and get.id or ''
		local f = get_ops[operation]
		local content, err = f(app, node_id, get)
		if content then
			return lwf.json(self, content)
		else
			return self:exit(500, err)
		end
	end,
	post = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		end
		local using_beta = ioe.beta()
		if not using_beta then
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		local app = post.app
		local operation = post.operation
		local node_id = post.id
		local f = post_ops[operation]
		local content, err = f(app, node_id, post)
		if content then
			return lwf.json(self, content)
		else
			return self:exit(500, err)
		end
	end,
}
