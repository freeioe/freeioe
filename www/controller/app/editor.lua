local snax = require 'skynet.snax'
local lfs = require 'lfs'


local function get_file_ext(filename)
	local ext = string.match(filename, '%.(%w-)$')
	return ext or 'unknown'
end

local function path_join(...)
	return table.concat({...}, '/')
end

local function get_app_path(app, ...)
	return path_join("./iot/apps", app, ...)
end

local function list_nodes(app, sub)
	local nodes = {}
	local directory = get_app_path(app, sub)
	for filename in lfs.dir(directory) do
		if filename ~= '.' and filename ~= '..' and string.sub(filename, -1) ~= '~' then
			local id = path_join(sub, filename)
			local mode = lfs.attributes(directory..'/'..filename, 'mode')
			if 'file' == mode then
				nodes[#nodes + 1] = {
					id = id,
					text = filename,
					children = false,
					['type'] = 'file',
					icon = 'file file-'..get_file_ext(filename)
				}
			end
			if 'directory' == mode then
				nodes[#nodes + 1] = {
					id = id,
					text = filename,
					children = true,
					['type'] = 'folder',
					icon = 'folder'
				}
			end
		end
	end
	if #nodes > 0 then
		return nodes
	else
		return '[]'
	end
end

local get_ops = {
	get_node = function(app, node, opt)
		if node == '#' then
			-- this is root
			local root = {
				id = "/",
				text = app,
				['type'] = 'folder',
				icon = 'folder',
				state = {
					opened = true,
					disabled = true,
				},
				children = list_nodes(app, "")
			}
			return {root}
		else
			list_nodes(app, node)
		end
	end,
	create_node = function(app, node, opt)
		file_type = opt['type']
		name = opt.text
		-- TODO:
	end,
	rename_node = function(app, node, opt)
		new_name = opt.text
	end,
	move_node = function(app, node, opt)
		dst = opt.parent ~= '/' and opt.parent or ''
	end,
	delete_node = function(app, node, opt)
		dst = opt.parent
		if dst ~= '/' then
			-- TODO:
		end
	end,
	copy_node = function(app, node, opt)
		dst = opt.parent ~= '/' and opt.parent or ''
	end,
	get_content = function(app, node, opt)
		local path = get_app_path(app, node)
		local f = assert(io.open(path, 'r'))
		local content = f:read('a')
		f:close()
		return {
			['type'] = get_file_ext(node),
			content = content
		}
	end,
}

local post_ops = {
	set_content = function(app, node, opt)
	end,
}

return {
	get = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		end

		local get = ngx.req.get_uri_args()
		local app = get.app
		local operation = get.operation
		local node_id = get.id ~= '/' and get.id or ''
		local f = get_ops[operation]
		local content = f(app, node_id, get) or ''
		return lwf.json(self, content)
	end,
	post = function(self)
		if lwf.auth.user == 'Guest' then
			self:redirect('/user/login')
			return
		end

		ngx.req.read_body()
		local post = ngx.req.get_post_args()
		assert(post.inst)
		local appmgr = snax.uniqueservice('appmgr')
		local r, err = appmgr.req.start(post.inst)
		if r then
			ngx.print(_('Application started!'))
		else
			ngx.print(err)
		end
	end,
}
