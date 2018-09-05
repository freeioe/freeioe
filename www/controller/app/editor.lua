local snax = require 'skynet.snax'
local lfs = require 'lfs'
local dc = require 'skynet.datacenter'
local ioe = require 'ioe'

local function get_file_ext(filename)
	local ext = string.match(filename, '%.(%w-)$')
	return ext or 'text'
end

local function path_join(...)
	local path = table.concat({...}, '/')
	assert(not string.match(path, '%.%.'), "Cannot have .. in node id")
	return path
end

local function get_app_path(app, ...)
	local path = path_join("./ioe/apps", app, ...)
	path = string.gsub(path, "\\", "/")
	return path
end

local function basename(path)
	return string.match(path, '^.-/([^/]+)$') or path
end

local function dirname(path)
	return string.match(path, '^(.+)/[^/]+$') or ''
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
			return list_nodes(app, node)
		end
	end,
	create_node = function(app, node, opt)
		file_type = opt['type']
		name = opt.text
		local id = path_join(node, name)
		if file_type == 'file' then
			local path = get_app_path(app, node, name)
			if lfs.attributes(path) then
				return nil, "File already exits"
			end
			local f = assert(io.open(path, 'w+'))
			f:close()
			return {
				id = id,
				icon = "file file-"..get_file_ext(name)
			}
		else
			local path = get_app_path(app, node, name)
			lfs.mkdir(path)
			return {
				id = id
			}
		end
	end,
	rename_node = function(app, node, opt)
		if node == '/' then
			return nil, "cannot rename root"
		end
		new_name = opt.text
		local path = get_app_path(app, node)
		local new_node = path_join(dirname(node), new_name)
		local new_path = get_app_path(app, new_node)
		assert(os.rename(path, new_path))
		local mode = lfs.attributes(new_path, 'mode')
		if mode == 'file' then
			return {
				id = new_node,
				icon = 'file file-'..get_file_ext(new_node)
			}
		else
			return {
				id = new_node
			}
		end
	end,
	move_node = function(app, node, opt)
		local dst = opt.parent ~= '/' and opt.parent or ''
		local dst_path = get_app_path(app, dst)..'/'
		os.execute('mv '..get_app_path(app, node)..' '..dst_path)
		return { 
			id = path_join(dst, basename(node))
		}
	end,
	delete_node = function(app, node, opt)
		if node == '/' then
			return nil, "cannot delete root"
		end
		local path = get_app_path(app, node)
		local mode = lfs.attributes(path, 'mode')
		if mode == 'file' then
			assert(os.remove(path))
			return { status = 'OK' }
		end
		if mode == 'directory' then
			assert(lfs.rmdir(path))
			return { status = 'OK' }
		end
	end,
	copy_node = function(app, node, opt)
		local dst = opt.parent ~= '/' and opt.parent or ''
		local dst_path = get_app_path(app, dst)..'/'
		os.execute('cp -r '..get_app_path(app, node)..' '..dst_path)
		return { status = 'OK' }
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
		local content = opt.text
		if string.len(content) > 4 * 1024 * 1024 then
			return { status = 'Failed' }
		end
		local path = get_app_path(app, node)
		local f = assert(io.open(path, 'w'))
		f:write(content)
		f:close()
		local appmgr = snax.uniqueservice("appmgr")
		appmgr.post.app_modified(app, 'web_editor')
		return { status = 'OK' }
	end,
	set_content_ex = function(app, node, opt)
		local content = opt.text
		local path = get_app_path(app, node)
		local f, err = io.open(path, 'w')
		if not f then
			local folder = string.match(path, "(.+)[/]")
			if not folder then
				return { status = 'Failed' }
			end
			os.execute('mkdir -p '..folder)
			f, err = io.open(path, 'w')
		end
		f:write(content)
		f:close()
		local appmgr = snax.uniqueservice("appmgr")
		appmgr.post.app_modified(app, 'web_editor')
		return { status = 'OK' }
	end,
}

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
