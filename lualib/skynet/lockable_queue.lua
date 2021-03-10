local skynet = require "skynet"
local coroutine = coroutine
local xpcall = xpcall
local traceback = debug.traceback
local table = table

--- Parent queue, and where lock the parent
function skynet.lockable_queue(parent_queue, parent_lock)
	local current_thread = nil
	local ref = 0
	local thread_queue = {}
	local parent_queue = parent_queue
	local parent_lock = parent_lock
	local locked_by = nil

	local function xpcall_ret(ok, ...)
		ref = ref - 1
		if ref == 0 then
			if locked_by == current_thread then
				locked_by = nil
			end
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
		--- If queue is locked and current thread is not the running one
		if locked_by and current_thread ~= thread then
			return nil, "Queue is locked"
		end

		--- Set the locked flag even current task is not running for avoid any new task comming
		if lock then
			locked_by = thread
		end

		--- If not in recursive lock, and current is running, wait for previous one finished
		if current_thread and current_thread ~= thread then
			table.insert(thread_queue, thread)
			skynet.wait()
			assert(ref == 0)	-- current_thread == thread
		end

		--- Set the current running thread
		current_thread = thread

		--- Increase the ref
		ref = ref + 1

		--- Execute the function
		return xpcall_ret(xpcall(f, traceback, ...))
	end

	if parent_queue then 
		return function(f, lock, ...)
			return parent_queue(lockable_queue, parent_lock, f, lock, ...)
			--[[
			return parent_queue(function(...)
				return lockable_queue(f, lock, ...)
			end, parent_lock, ...)
			]]--
		end
	else
		return lockable_queue
	end
end

--- 
-- Lockable queue
-- @tparam function f The function to execute in this queue
-- @tparam boolean lock Lock current queue until current task exeucted completely or task cloud be queued for execution
-- @param ...
-- @return false if queue is lock, or the first value from your function f
-- @returns
return skynet.lockable_queue
