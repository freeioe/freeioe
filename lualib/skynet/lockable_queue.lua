local skynet = require "skynet"
local coroutine = coroutine
local xpcall = xpcall
local traceback = debug.traceback
local table = table

function skynet.lockable_queue(parent_queue, parent_lock)
	local current_thread
	local ref = 0
	local thread_queue = {}
	local parent_queue = parent_queue
	local parent_lock = parent_lock
	local locked 

	local function xpcall_ret(ok, ...)
		ref = ref - 1
		if ref == 0 then
			locked = nil
			current_thread = table.remove(thread_queue,1)
			if current_thread then
				skynet.wakeup(current_thread)
			end
		end
		if not ok then
			return nil, ...
		end
		--assert(ok, (...))
		return ...
	end

	local lockable_queue = function(f, lock, ...)

		local thread = coroutine.running()
		if locked and current_thread ~= thread then
			return nil, "Queue is locked"
		end
		locked = locked or lock
		if current_thread and current_thread ~= thread then
			table.insert(thread_queue, thread)
			skynet.wait()
			assert(ref == 0)	-- current_thread == thread
		end
		current_thread = thread

		ref = ref + 1
		return xpcall_ret(xpcall(f, traceback, ...))
	end

	if parent_queue then 
		return function(f, lock, ...)
			return parent_queue(lockable_queue, parent_lock, f, lock, ...)
		end
	else
		return lockable_queue
	end
end

--- 
-- Lockable queue
-- @tparam function f The function to execute in this queue
-- @tparam boolean lock Lock current queue until current task executed or unlock by llock(nil, true)
-- @param ...
-- @return false if queue is lock, or the first value from your function f
-- @returns
return skynet.lockable_queue
