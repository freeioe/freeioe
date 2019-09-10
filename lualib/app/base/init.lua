local class = require 'middleclass'
local app_conf = require 'app.conf'

local app = class('BASIC_APP_CLASS')
app.static.API_VER = 4

function app:initialize(name, sys, conf)
	assert(name and sys and conf, "Missing parameter in initialize")
	self._name = name
	self._sys = sys
	self._conf = app_conf:new(sys)(conf)
	self._api = self._sys:data_api()
	self._log = sys:logger()

	self:on_init()

	self._safe_call = function(f, ...)
		local r, er, err = xpcall(f, debug.traceback, ...)
		if not r then
			self._log:warning('Code bug', er, err)
			return nil, er and tostring(er) or nil
		end
		return er, tostring(err) or nil
	end
end

function app:on_init()
	---
end

function app:on_start()
	self._log:trace("Default simple application on_start used.")
end

function app:on_close(reason)
	self._log:trace("Default simple application on_stop used.")
end

local function __map_handler(handler, app, func)
	local f = app[func]
	if f then
		--app._log:trace("Application has handler:", func)
		handler[func] = function(...)
			return app._safe_call(f, app, ...)
		end
	end
end

function app:_map_handler()
	local handler = {}

	__map_handler(handler, self, 'on_add_device')
	__map_handler(handler, self, 'on_mod_device')
	__map_handler(handler, self, 'on_del_device')

	__map_handler(handler, self, 'on_input')
	__map_handler(handler, self, 'on_input_em')

	__map_handler(handler, self, 'on_output')
	__map_handler(handler, self, 'on_output_result')

	__map_handler(handler, self, 'on_command')
	__map_handler(handler, self, 'on_command_result')

	__map_handler(handler, self, 'on_ctrl')
	__map_handler(handler, self, 'on_ctrl_result')

	__map_handler(handler, self, 'on_comm')
	__map_handler(handler, self, 'on_stat')
	__map_handler(handler, self, 'on_event')

	if self._calc then
		self._calc:start(handler)
	else
		self.__calc_assert = true
	end

	return handler, handler.on_input ~= nil
end

function app:start()
	self._api:set_handler(self:_map_handler())

	return self:on_start()
end

function app:close(reason)
	if self._calc then
		self._calc:stop()
		self._calc = nil
	end

	return self:on_close(reason)
end

function app:run(tms)
	if self.on_run then
		return self:on_run(tms)
	end
	return 60 * 1000
end

--- Utilities functions
--- Generate unique id, depends on gateway id and hashing from key
function app:gen_sn(key)
	return string.format('%s.%s', self._sys:id(), self._sys:gen_sn(key))
end

function app:create_calc()
	assert(not self.__calc_assert, "create_calc only can be called in on_init function")

	if not self._calc then
		local app_calc = require 'app.utils.calc'
		self._calc = app_calc(self._sys, self._api, self._log)
	end
	return self._calc
end

function app:get_calc()
	assert(self._calc)
	return self._calc
end

return app

