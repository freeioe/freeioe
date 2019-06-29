local class = require 'middleclass'
local ping_pong = require 'hwtest.stream.ping_pong'


local ms = class("PORT_TEST_PAIR_MASTER_SLAVE")

function ms:initialize(count, max_msg_size)
	self._max_count = count or 1000

	self._slave = ping_pong:new(count, max_msg_size, false)
	self._master = ping_pong:new(count, max_msg_size, true)
end

function ms:start(master, slave)
	return self._slave:start(slave) and self._master:start(master)
end

function ms:finished()
	return self._master:finished() and self._slave:finished()
end

function ms:report()
	return {
		master = self._master:report(),
		slave = self._slave:report(),
	}
end

return ms
