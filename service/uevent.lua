--[[
-- Kernel uevent message handler service
-- Reads uevent messages from kernel and notifies hardware changes
--
-- Features:
-- - Monitors kernel uevent messages for hardware changes
-- - Parses uevent messages and publishes to multicast channel
-- - Automatic retry on uevent connection failures
-- - Bounded message buffer to prevent memory leaks
--
--]]

local skynet = require 'skynet.manager'
local mc = require 'skynet.multicast'
local uevent_loaded, uevent = pcall(require, 'luevent')
local inspect = require 'inspect'
local log = require 'utils.logger'.new('UEVENT')

-- ============================================================================
-- Constants
-- ============================================================================

local MAX_UEVENT_MSG_LIST_SIZE = 1000
local UEVENT_SLEEP_INTERVAL = 5   -- sleep between uevent runs (50ms)

-- ============================================================================
-- Module State
-- ============================================================================

local uevent_chn = nil
local uevent_msg_list = {}

-- ============================================================================
-- Internal Functions
-- ============================================================================

---
-- Handle parsed uevent message
-- @param msg: parsed uevent message table
---
local handle_uevent_msg = function(msg)
	if not msg or type(msg) ~= 'table' then
		log:warning('Invalid uevent message, skipping')
		return
	end

	-- Manage buffer size to prevent unbounded growth
	if #uevent_msg_list >= MAX_UEVENT_MSG_LIST_SIZE then
		-- Remove oldest messages
		local remove_count = math.floor(MAX_UEVENT_MSG_LIST_SIZE / 10)
		for i = 1, remove_count do
			table.remove(uevent_msg_list, 1)
		end
		log:warning('UEvent message buffer full, removed', remove_count, 'old messages')
	end

	table.insert(uevent_msg_list, msg)
end

---
-- Parse and handle raw uevent message string
-- @param msg: raw uevent message string
---
local handle_msg = function(msg)
	if not msg or type(msg) ~= 'string' then
		return
	end

	-- Skip libudev messages
	if string.lower(string.sub(msg, 1, 7)) == 'libudev' then
		return
	end

	-- Tokenize message
	local t = {}
	for w in string.gmatch(msg, "%g+") do
		t[#t + 1] = w
	end

	if #t == 0 then
		log:warning('Empty uevent message')
		return
	end

	-- Parse action and devpath from first token
	local t1 = t[1]
	local action, devpath = string.match(t1, "^([^@]+)@(.+)")
	if not action or not devpath then
		log:warning('Cannot parse action/devpath from:', t1)
		return
	end

	-- Parse key=value pairs
	local tmsg = {}
	for i, v in ipairs(t) do
		if i ~= 1 then
			local key, val = string.match(v, '(.-)=(.+)')
			if key and val then
				tmsg[key] = val
			else
				log:trace('Cannot parse uevent field:', v)
			end
		end
	end

	-- Validate parsed fields match
	if action ~= tmsg.ACTION then
		log:error('Action mismatch:', action, 'vs', tmsg.ACTION)
		return
	end

	if devpath ~= tmsg.DEVPATH then
		log:error('Devpath mismatch:', devpath, 'vs', tmsg.DEVPATH)
		return
	end

	return handle_uevent_msg(tmsg)
end

---
-- Publish accumulated uevent messages to multicast channel
---
local publish_uevent_messages = function()
	if not uevent_chn or #uevent_msg_list == 0 then
		return
	end

	for _, v in ipairs(uevent_msg_list) do
		uevent_chn:publish(v)
	end

	-- Clear published messages
	uevent_msg_list = {}
end

-- ============================================================================
-- Command Interface
-- ============================================================================

local command = {}

---
-- Get uevent multicast channel
-- @return: channel object
---
function command.CHANNEL()
	return uevent_chn and uevent_chn.channel or nil
end

-- ============================================================================
-- Service Lifecycle
-- ============================================================================

skynet.start(function()
	uevent_chn = mc.new()

	-- Register command handlers
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[string.upper(cmd)]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s from session %s-%s", tostring(cmd), tostring(session), tostring(address)))
		end
	end)

	-- Start uevent monitoring
	skynet.fork(function()
		if not uevent_loaded then
			log:error("luevent module not found, uevent service disabled")
			return
		end

		-- Create uevent connection
		local uevent_conn = uevent.new(function(msg)
			return handle_msg(msg)
		end)

		log:notice("UEvent monitoring started")

		-- Main uevent processing loop with retry logic
		while true do
			local r, err = uevent_conn:run()
			if not r then
				log:error('UEvent run failed:', err)
			end

			-- Publish any accumulated messages before retry
			publish_uevent_messages()
			-- Added sleep to handle skynet messages
			skynet.sleep(UEVENT_SLEEP_INTERVAL)
		end
	end)

	skynet.register ".uevent"
	log.notice("UEvent service started!")
end)
