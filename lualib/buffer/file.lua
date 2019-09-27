local class = require 'middleclass'
local skynet = require 'skynet'
local zlib_loaded, zlib = pcall(require, 'zlib')
local cjson = require 'cjson.safe'
local lfs = require 'lfs'
local log = require 'utils.log'

local fb = class("File_Buffer_Utils")

function fb:initialize(file_folder, data_count_per_file, max_file_count, max_batch_size)
	self._file_folder = file_folder
	self._data_count_per_file = data_count_per_file
	self._max_file_count = max_file_count
	self._max_batch_size = max_batch_size
	self._files = {} -- file list that already in disk
	self._buffer = {} -- data buffer list
	self._fire_buffer = {}
	self._fire_offset = 1 -- buffer offset.
	self._fire_index = nil -- file index. nil means there is no fire_buffer (file or buffer)
	self._hash = 'FILE_BUF_UTILS_V1'

	self._stop = nil
end

function fb:dump_index()
	return cjson.encode({
		hash = self._hash,
		fire_index = self._fire_index,
		fire_offset = self._fire_offset,
		files = self._files,
	})
end

function fb:load_index(string)
	local data = cjson.decode(string)
	if data.hash ~= self._hash then
		return nil, "Not valid hash readed!"
	end

	self._files = data.files
	self._buffer = self._load_next_file()
	if not self._fire_index == data.fire_index then
		self._fire_offset = data.fire_offset
	else
		log.warning("Loaded different file index, reset offset.", self._fire_index, data.fire_index, data.fire_offset)
		self._fire_offset = 1
	end

	return true
end

function fb:push(...)
	if self:empty() then
		if self._callback(...) then
			return true
		end
	end
	self:_push(...)
	return false
end

-- callback that return true/false
function fb:start(data_callback, batch_callback)
	assert(data_callback)
	self._callback = data_callback
	self._stop = nil

	--- make sure the folder exits
	lfs.mkdir(self._file_folder)
	assert(lfs.attributes(self._file_folder, 'mode') == 'directory')

	skynet.fork(function()
		while not self._stop and self._callback do
			local sleep_gap = 100
			if batch_callback then
				sleep_gap = self:_try_fire_data_batch(batch_callback)
			else
				sleep_gap = self:_try_fire_data()
			end

			skynet.sleep(sleep_gap or 100, self)
		end
	end)
end

function fb:stop()
	if not self._stop then
		self._stop = true
		skynet.wakeup(self)
	end
end

--- check if buffer empty
function fb:empty()
	return #self._files == 0 and #self._buffer == 0 and #self._fire_buffer == 0
end

function fb:size()
	local fire_left = #self._fire_buffer - self._fire_offset + 1

	local file_count = #self._files
	if file_count > 0 and self._files[0] ~= self._fire_index then
		file_count = file_count - 1
	end

	return #self._buffer + fire_left + (file_count  * self._data_count_per_file)
end

--- Create buffer file path
function fb:_make_file_path(index)
	return self._file_folder.."/cache."..index
end

---
function fb:_dump_buffer_to_file(buffer)
	local str, err = cjson.encode(buffer)
	if not str then
		return nil, err
	end

	local index = ((self._fire_index or 1) + #self._files) % 0xFFFFFFFF
	local file_path = self:_make_file_path(index)
	local f, err = io.open(file_path, "w+")
	if not f then
		log.error("Failed to create data cache file", err)
		return nil, err
	end

	str = self:_compress(str)

	--print('dump', index, str)
	log.debug("Saving data cache to file:", file_path, 'count:', #buffer, 'size:', string.len(str))

	f:write(str)
	f:close()

	self._files[#self._files + 1] = index

	--- Set proper fire stuff
	if not self._fire_index then
		self._fire_index = index
		self._fire_buffer = buffer
		self._fire_offset = 1
	end

	--- remove the too old files
	if #self._files > self._max_file_count then
		--print('drop '..self._fire_index)
		--- load index and buffer
		self._fire_buffer = self:_load_next_file()
		--- reset offset
		self._fire_offset = 1
	end
end

function fb:_push(...)
	--- append to buffer
	self._buffer[#self._buffer + 1] = {...}

	-- print(#self._buffer)

	--- dump to file if data count reach
	if #self._buffer >= self._data_count_per_file then
		self:_dump_buffer_to_file(self._buffer)
		self._buffer = {}
	end
end

function fb:_load_next_file()
	--- pop fired file
	if self._fire_index and self._files[1] == self._fire_index then
		table.remove(self._files, 1)
		os.remove(self:_make_file_path(self._fire_index))
	end

	-- until we got one correct file
	while #self._files > 0 do
		-- get first index
		local index = self._files[1]

		-- Open file
		--print('load ', index)
		local file_path = self:_make_file_path(index)
		log.debug("Loading data cache from file:", file_path)

		local f, err = io.open(file_path)
		if f then
			--- read all file
			local str = f:read('a')
			f:close()

			--- set the current index
			self._fire_index = index

			if str then
				--- if read ok decode content
				local dstr = self:_decompress(str)
				local buffer, err = cjson.decode(dstr)
				if buffer then
					--- if decode ok return
					return buffer
				else
					log.error('Decode data cache error! Index: ', index, err)
				end
			else
				log.error('Read data cache file error! Index: ', index)
			end
		end

		-- continue with next file
		table.remove(self._files, 1)
		os.remove(self:_make_file_path(index))
	end

	-- no next file
	self._fire_index = nil
	return {}
end

function fb:_pop(first)
	--- increase offset
	if not first then
		self._fire_offset = self._fire_offset  + 1
	end

	--- if fire_buffer already done
	if #self._fire_buffer < self._fire_offset then
		self._fire_buffer = self:_load_next_file()
		self._fire_offset = 1
	end

	--- load empty then check current buffer
	if #self._fire_buffer == 0 then
		if #self._buffer == 0 then
			self._fire_offset = 1
			--- no more data
			return nil
		else
			--- pop not dumped buffer
			self._fire_buffer = self._buffer
			self._fire_offset = 1
			self._buffer = {}
		end
	end

	return self._fire_buffer[self._fire_offset]
end

function fb:_try_fire_data()
	local callback = self._callback
	local first = true

	while not self:empty() do
		local data = self:_pop(first)
		if not data then
			assert(self._fire_index == nil)
			assert(self._fire_offset == 1)
			assert(#self._fire_buffer == 0)
			assert(#self._files == 0)
			assert(#self._buffer == 0)
			--- Finished fire
			break
		end

		local r, done, err = pcall(callback, table.unpack(data))
		if not r then
			log.warning('Buffer_file callback bug', done, err)
			break
		end

		if not done then
			--- Fire not available
			break
		end

		first = false
	end
end

--- Fire data in batch array.
function fb:_try_fire_data_batch(callback)
	while not self:empty() do
		--- Make sure fire_buffer not changed
		local working_index = self._fire_index

		--- dump current buffer to file and fire them
		if not working_index and #self._files == 0 then
			self:_dump_buffer_to_file(self._buffer)
			self._buffer = {}
			working_index = self._fire_index
		end

		--- callback
		local buf = self._fire_buffer
		local offset = self._fire_offset
		if self._max_batch_size and self._max_batch_size < #buf then
			buf = table.move(buf, offset, offset + self._max_batch_size - 1, 1, {})
			offset = 1
			assert(#buf <= self._max_batch_size)
		end

		local r, done, err = pcall(callback, buf, offset)
		if not r then
			log.warning('Buffer_file callback bug', done, err)
			break
		end

		if not done then
			--- Fire not available
			break
		end

		--print('done', done, ' from offset', self._fire_offset)

		--- if index equal means the self._fire_buffer is valid one
		if working_index == self._fire_index then
			self._fire_offset = self._fire_offset + tonumber(done)

			--- if fire_buffer already done
			if #self._fire_buffer < self._fire_offset then
				self._fire_buffer = self:_load_next_file()
				self._fire_offset = 1
			end
			--- only process the dumped files buffer and the current buffer will be dumped in nex loop
		end
	end
end

function fb:_compress(data)
	if not zlib_loaded then
		return data
	end
	local deflate = zlib.deflate()
	return deflate(data, 'finish')
end

function fb:_decompress(data)
	if not zlib_loaded then
		return data
	end
	local inflate = zlib.inflate()
	return inflate(data, "finish")
end

function fb:__test_a()
	local o = fb:new('/tmp/aaaaa', 10, 10)

	local callback_ok = true
	local callback_check = 0
	local callback = function(data)
		assert(callback_check == data, "callback_check: "..callback_check.." data: "..data)
		if callback_ok then
			callback_check = callback_check + 1
			--print(data)
			return true
		end
		return false
	end
	o:start(callback)
	local data = 0
	--- push 200 data, ok done
	print('work', data)
	while data < 200 do
		o:push(data)
		data = data + 1
	end

	print('enter sleep')
	print(callback_check)
	skynet.sleep(10)
	assert(callback_check == 200)
	print('after sleep')

	--- push 200 data, lost 100
	callback_ok = false
	print('work', data)
	while data < 401 do
		o:push(data)
		data = data + 1
	end

	print('enter sleep')
	print(callback_check)
	skynet.sleep(10)
	assert(callback_check == 200)
	print('after sleep')

	--- callback ok
	callback_check = 300
	callback_ok = true
	skynet.sleep(200)
	assert(callback_check == 401)

	--- push another 200 data
	print('work', data)
	while data < 700 do
		o:push(data)
		data = data + 1
	end

	print('enter sleep')
	print(callback_check)
	skynet.sleep(10)
	assert(callback_check == 700)
	print('after sleep')

	o:stop()
end

function fb:__test_b()
	local o = fb:new('/tmp/aaaaa', 10, 10)

	local callback_ok = true
	local callback_check = 0
	local callback = function(data)
		assert(callback_check == data, "callback_check: "..callback_check.." data: "..data)
		if callback_ok then
			print('single:', data)

			callback_check = callback_check + 1
			return true
		end
		return false
	end

	local callback_batch = function(data, offset)
		local first_val = data[offset][1]
		assert(callback_check == first_val, "callback_check: "..callback_check.." data: "..first_val)
		if callback_ok then
			print('batch:', cjson.encode(data))

			local left = #data - offset + 1
			print('batch start:', callback_check, 'left:', left)
			assert(left > 0, "left zero data cout: "..#data.." offset: "..offset)
			left = left < 3 and left or 3
			callback_check = callback_check + left
			print('batch check', callback_check)
			return left
		end
		return nil
	end
	o:start(callback, callback_batch)
	local data = 0
	--- push 200 data, ok done
	print('work', data)
	while data < 200 do
		o:push(data)
		data = data + 1
	end

	print('enter sleep')
	print(callback_check)
	skynet.sleep(10)
	assert(callback_check == 200, "callback_check: "..callback_check.." data: 200")
	print('after sleep')

	--- push 200 data, lost 100
	callback_ok = false
	print('work', data)
	while data < 401 do
		o:push(data)
		data = data + 1
	end

	print('enter sleep')
	print(callback_check)
	skynet.sleep(10)
	assert(callback_check == 200, "callback_check: "..callback_check.." data: 200")
	print('after sleep')

	--- callback ok
	callback_check = 300
	callback_ok = true
	skynet.sleep(200)
	assert(callback_check == 401, "callback_check: "..callback_check.." data: 401")

	--- push another 200 data
	print('work', data)
	while data < 700 do
		o:push(data)
		data = data + 1
	end

	print('enter sleep')
	print(callback_check)
	skynet.sleep(10)
	assert(callback_check == 700, "callback_check: "..callback_check.." data: 700")
	print('after sleep')

	o:stop()
end

function fb:__test()
	self:__test_a()
	self:__test_b()
end

return fb
