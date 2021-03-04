local class = require 'middleclass'
local cjson = require 'cjson.safe'
local md5 = require 'md5'
local lfs = require 'lfs'

local file = class('freeioe.lib.utils.safe_file')

function file:initialize(file_path)
	assert(file_path, "File path missing")
	self._path = file_path
	self._data = {}
	self._md5sum = ''
	self._modification = 0
end

function file:_save_file(path, content, content_md5sum)
	local file, err = io.open(path, "w+")
	if not file then
		return nil, err
	end

	local mfile, merr = io.open(path..".md5", "w+")
	if not mfile then
		return nil, merr
	end
	self._modification = os.time()

	file:write(content)
	file:close()

	mfile:write(content_md5sum)
	mfile:close()

	return true
end

function file:update(data)
	local str = cjson.encode(data)
	local sum = md5.sumhexa(str)
	if sum == self._md5sum then
		return true, 'MD5SUM is same, skipped saving'
	end

	local r, err = self:_save_file(self._path, str, sum)
	if not r then
		return nil, err
	end
	self._data = data
	self._md5sum = sum
	return true
end

function file:load()
	local path = self._path
	self._modification = tonumber(lfs.attributes(path, 'modification'))
	local f, err = io.open(path, 'r')
	if not f then
		return nil, err
	end

	local str = f:read("*a")
	f:close()

	--- Check the configuration md5
	local sum = md5.sumhexa(str)
	local mfile = io.open(path..".md5", "r")
	if mfile then
		local md5s = mfile:read("*l")
		mfile:close()
		if md5s ~= sum then
			return nil, "Saved MD5 is :"..md5s..' Calced: '..sum
		end
	else
		local mfile, merr = io.open(path..".md5", "w+")
		if mfile then
			mfile:write(sum)
			mfile:close()
		end
	end

	local data, err = cjson.decode(str) or {}
	if not data then
		return nil, err
	end

	local str, err = cjson.encode(data)
	if not str then
		return nil, err
	end

	local sum = md5.sumhexa(str)

	self._md5sum = sum
	self._data = data

	return data
end

function file:data()
	return self._data
end

return file
