--- Load configuration
-- conf_cfg.port
--
local alt_getopt = require 'alt_getopt'
local log = require 'utils.log'

local arg = arg or {...}
local log_trace = log.trace
local log_info = log.info

local function param_from_opts(opts, sub_key)
	local param = {}
	local mk = '^conf[%._]'
	if sub_key then
		mk = mk..sub_key..'[%._]'
	end
	for k, v in pairs(opts) do
		local key = k:match(mk..'(.+)$')
		if key then
			log_trace('Configuration From Args:', key, ' = '..v)
			local t = param
			for v in key:gmatch('([^.]+)%.') do
				t[v] = t[v] or {}
				t = t[v]
			end
			key = key:match('([^.]+)$')
			if key then
				t[key] = v
			end
		end
	end

	return param
end

local function merge_table(td, ts, fpath)

	for k, v in pairs(ts) do
		local fpath = fpath and fpath..'.'..k or k
		if type(v) == 'table' then
			td[k] = td[k] or {}
			assert(type(td[k]) == 'table')
			merge_table(td[k], v, fpath)
		else
			log_trace('Configuration Overrided:', fpath, ' = '..v, ' [ '..tostring(td[k])..']')
			td[k] = v
		end
	end
end

--- Load configruation file
-- @tparam string name if option table has no c|conf then using this name ask the configuration name
-- @tparam table opts pre-parsed option table
-- @tparam boolean no_name_replace force using name parameter event option table has c|conf
-- @tparam string opt_sub_key default option table takes conf_(.+), by setting this it will be conf_<name>_(.+)
local function load_cfg(name, opts, no_name_replace, opt_sub_key)
	--- parse opts
	local opts = opts or alt_getopt.get_opts(arg, 'c:', {conf= 'c'})
	--- loading conf.logger.lua
	local pkg = 'conf.'..(opts.c or opts.conf or name or '__error')
	if no_name_replace then
		pkg = 'conf.'..(name or pkg or '__error') -- make sure we  has one string
	end
	log_info('Configuration Loading', pkg)
	local cfg = require(pkg)
	local param = param_from_opts(opts, opt_sub_key)
	merge_table(cfg, param)
	return cfg
end


local function test()
	local param_sub = param_from_opts({
		cfg = 111,
		['conf.logger.aae'] = 222,
		['conf.logger.aaa.dfa'] = 222,
		['conf_logger_aba.afa'] = '1232c',
		c = 'add'
	}, 'logger')
	assert(param_sub.aae == 222)
	assert(param_sub.aaa and type(param_sub.aaa) == 'table' and param_sub.aaa.dfa == 222)
	assert(param_sub.aba and type(param_sub.aba) == 'table' and param_sub.aba.afa == '1232c')

	local param = param_from_opts({
		cfg = 111,
		['conf.aae'] = 222,
		['conf.aaa.dfa'] = 222,
		['conf_aba.afa'] = '1232c',
		c = 'add'
	})
	assert(param.aae == 222)
	assert(param.aaa and type(param.aaa) == 'table' and param.aaa.dfa == 222)
	assert(param.aba and type(param.aba) == 'table' and param.aba.afa == '1232c')

	local cfg = {
		abc = {
			ava = 222,
			dddd = 555,
		},
		aae = 333,
		aaa = {
			bbb = 'bbb',
			dfa = 333,
		},
		afa = {
			bbb = 'bbb',
			afa = 'abc',
		},
	}
	merge_table(cfg, param)
	assert(cfg.abc.ava == 222)
	assert(cfg.abc.dddd == 555)
	assert(cfg.aae == 222)
	assert(cfg.aaa.bbb == 'bbb')
	assert(cfg.aaa.dfa == 222)
	assert(cfg.afa.bbb == 'bbb')
	assert(cfg.afa.afa == 'abc')
end


--test()

return load_cfg
