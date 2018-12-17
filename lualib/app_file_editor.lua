local snax = require 'skynet.snax'
local dc = require 'skynet.datacenter'
local uuid = require 'uuid'
local lfs = require 'lfs'
local ioe = require 'ioe'

local pack_target_path = "/tmp/ioe/"

local function get_file_ext(filename)
	local ext = string.match(filename, '%.(%w-)$')
	return ext or 'text'
end

local function path_join(...)
	--local path = table.concat({...}, '/'):gsub("//","/"):gsub("//","/")
	local path = table.concat({...}, '/')
	assert(not string.match(path, '%.%.'), "Cannot have .. in node id")
	return path
end

local function get_app_path(app, ...)
	local path = path_join("./ioe/apps", app, ...)
	--path = string.gsub(path, "\\", "/"):gsub("//", "/"):gsub("//","/")
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

local function stat_node(app, sub)
	local path = get_app_path(app, sub)
	local mode = lfs.attributes(path, 'mode')
	local access = lfs.attributes(path, 'access')
	local modification = lfs.attributes(path, 'modification')
	local size = lfs.attributes(path, 'size')

	return {
		id = sub,
		mode = mode,
		access = access,
		modification = modification,
		size = size
	}
end

local function pack_app(inst, version)
	if not inst then
		return nil, "Application instance missing"
	end

	local version = version or uuid.new()
	local app = dc.get("APPS", inst)

	--local target_file = inst.."_v"..version..".tar.gz"
	local target_file = inst.."_ver_"..version..".zip"
	local target_file_escape = string.gsub(target_file, " ", "__")
	os.execute("mkdir -p "..pack_target_path)
	os.execute("rm -f "..pack_target_path..target_file_escape)

	--local cmd = "tar -cvzf "..pack_target_path..target_file_escape.." "..string.gsub(get_app_path(inst, "*"), " ", "\\ ")
	local cmd = "cd "..string.gsub(get_app_path(inst), " ", "\\ ").." && zip -r -q "..pack_target_path..target_file_escape.." ./*"
	local r, status, code = os.execute(cmd)
	if not r then
		return nil, "failed to pack application"..inst
	end
	return target_file_escape
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
	stat_node = function(app, node, opt)
		if node == '#' then
			node = "/"
		end
		return {
			id = node,
			stat = stat_node(app, node)
		}
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
		local ext = get_file_ext(node)
		local mode = lfs.attributes(path, 'mode')
		local size = lfs.attributes(path, 'size')
		if ext ~= 'so' and mode == 'file' and size < 4 * 1024 * 1024  then
			local f = assert(io.open(path, 'r'))
			local content = f:read('a')
			f:close()
			return {
				['type'] = ext,
				content = content
			}
		else
			return {
				['type'] = ext,
			}
		end
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
		local appmgr = snax.queryservice("appmgr")
		appmgr.post.app_modified(app, 'web_editor')
		return { status = 'OK' }
	end,
	set_content_ex = function(app, node, opt)
		local content = opt.text
		if string.len(content) > 4 * 1024 * 1024 then
			return { status = 'Failed' }
		end
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
		local appmgr = snax.queryservice("appmgr")
		appmgr.post.app_modified(app, 'web_editor')
		return { status = 'OK' }
	end,
	pack_app = pack_app,
}

return {
	get_ops = get_ops,
	post_ops = post_ops,
	app_pack_path = pack_target_path,
}
