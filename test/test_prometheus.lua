local cjson = require 'cjson.safe'
local skynet = require 'skynet'
local metric = require 'db.prometheus.metric'
local database = require 'db.prometheus.database'

skynet.start(function()
	skynet.fork(function()
		local db = database:new({
			host = '127.0.0.1',
			port = 8428,
			url = '/api/v1/import/prometheus'
		})
		while true do
			local m = metric:new('SAMPLE.w00000')
			local now = skynet.time() - 1
			for i = 1, 1000 do
				m:push_value(math.random(1, 100), now + i / 1000)
			end
			local start = skynet.hpc()
			print('Prometheus push result', db:insert_metric(m))
			print('Prometheus push takes', (skynet.hpc() - start) / 1000000, 'ms')

			db:query('SAMPLE.w00000', now)
			db:query('SAMPLE.w00000', now + 1)

			local data, err = db:query_range("SAMPLE.w00000", now - 0.5, now + 1.5)
			if data then
				for _, v in ipairs(data.result) do
					if v.metric.__name__ == 'SAMPLE.w00000' then
						if v.values then
							print('Prometheus query count', #v.values)
						else
							print('Prometheus query count', v.value and 1 or 0)
						end
					end
				end
			end
			print('Prometheus query takes', (skynet.hpc() - start) / 1000000, 'ms')

			skynet.sleep(200)
		end
	end)
end)
