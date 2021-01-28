local skynet = require 'skynet'
local siri_client = require 'db.siridb.client'
local siri_database = require 'db.siridb.database'
local series = require 'db.siridb.series'

skynet.start(function()
	skynet.fork(function()
		local client = siri_client:new({}, 'test1')
		print('siridb version', client:get_version())
		print('siridb new_db', client:new_database('test1'))
		print('siridb list_db', client:get_databases())

		local db = siri_database:new({})

		while true do
			local s = series:new('SAMPLE.w00000')
			local now = skynet.time() - 1
			for i = 1, 1000 do
				s:push_value(math.random(1, 100), now + i / 1000)
			end
			local start = skynet.hpc()
			print('siridb insert', db:insert_series(s))
			print('siridb insert takes', (skynet.hpc() - start) / 1000000, 'ms')
			start = skynet.hpc()
			local data, err = db:query('select * from "SAMPLE.w00000" after now - 2s ', 'ms')
			if data then
				if not data['SAMPLE.w00000'] then
					print('siridb query count: 0')
				else
					print('siridb query count', #data['SAMPLE.w00000'])
				end
			end
			print('siridb query takes', (skynet.hpc() - start) / 1000000, 'ms')
			skynet.sleep(200)
		end
	end)
end)
