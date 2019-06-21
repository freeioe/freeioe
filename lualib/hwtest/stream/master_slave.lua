local class = require 'middleclass'
local ping_pong = require 'pair_test.ping_pong'


local ms = class("PORT_TEST_PAIR_MASTER_SLAVE")

function ms:initialize(app, count, max_msg_size)
	self._app = app
	self._sys = app._sys
	self._log = app._log
	self._max_count = count or 1000

	self._master = ping_pong:new(app, count, max_msg_size, true)
	self._slave = ping_pong:new(app, count, max_msg_size, false)
end

function ms:start(master, slave)
	return self._master:start(master) and self._slave:start(slave)
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
