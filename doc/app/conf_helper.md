
---

# 云配置帮助接口


本接口为采集类应用封装了从云配置服务中加载设备模板的逻辑。帮助用户快速使用云配置服务。


### initialize
> function helper:initialize(sys_api, conf, templates_ext, templates_dir, templates_node, devices_node)

构造函数。参数:

* sys_api - 应用系统接口 app.sys
* conf - 应用配置数据 (table数据或者{CNF_NAME}.{VERSION}字符串)
* templates_ext - 设备模板文件本地存储的扩展名。默认为csv
* templates_dir - 设备模板文件本地存储的子目录名。 默认为tpl
* templates_node - 应用配置数据中模板列表节点名称。默认为tpls。如果该节点为空，则不进行模板下载。
* devices_node - 应用配置数据中设备列表节点名称。默认为devs


> 注:
> 1. 当conf为字符串时，helper会从云配置接口获取对应的配置文件，然后使用json格式解析后当作应用配置数据使用。
> 2. 当conf字符串中不包含version时，如"CNF000000001"，helper会从云配置服务中获取最新版本进行下载
>


### fetch
> function api:fetch(async)

获取所有设备模板数据文件。async为true时将开启异步获取模式。


### templates
> function api:templates()

获取已经完成获取的模板列表


### devices
> function api:devices()

获取已经完成设备模板的设备列表


### 使用代码示例：

代码:

``` lua
	local config = self._conf or {}
	--[[
	config.devs = config.devs or {
		{ unit = 1, name = 'bms01', sn = 'xxx-xx-1', tpl = 'bms' },
		{ unit = 2, name = 'bms02', sn = 'xxx-xx-2', tpl = 'bms2' }
	}
	]]--

	--- 获取云配置
	if not config.devs or config.cnf then
		if not config.cnf then
			config = 'CNF000000002.1' -- loading cloud configuration CNF000000002 version 1
		else
			config = config.cnf .. '.' .. config.ver
		end
	end

	local helper = conf_helper:new(self._sys, config)
	helper:fetch()

	self._devs = {}
	for _, v in ipairs(helper:devices()) do
		-- initialize your devices
	end

	--- 获取配置
	local conf = helper:config()
	conf.channel_type = conf.channel_type or 'socket'
	if conf.channel_type == 'socket' then
		conf.opt = conf.opt or {
			host = "127.0.0.1",
			port = 1503,
			nodelay = true
		}
	else
		conf.opt = conf.opt or {
			port = "/dev/ttymxc1",
			baudrate = 115200
		}
	end
	if conf.channel_type == 'socket' then
		client = sm_client(socketchannel, conf.opt, modbus.apdu_tcp, 1)
```

获取完成后文件目录：
```
tpl/
├── CNF000000001_1.cnf
├── TPL000000001_1.csv
├── tpl1.csv
└── tpl2.csv
 
```

应用配置数据示例(CNF000000001):

``` json
{
	"opt": {
		"port": "/dev/ttymxc1",
		"baudrate": 19200
	},
	"tpls": [{
			"id": "TPL000000001",
			"name": "tpl1",
			"ver": 1
		},
		{
			"id": "TPL000000001",
			"name": "tpl2",
			"ver": 1
		}
	],
	"devs": [{
			"addr": 991122334455,
			"name": "s01",
			"sn": "xxx-xx-xx-1",
			"tpl": "tpl1"
		},
		{
			"addr": 112233445566,
			"name": "s02",
			"sn": "xxx-xx-xx-2",
			"tpl": "tpl2"
		}
	],
	"loop_gap": 3000
}
```

设备模板示例(TPL000000001)：

``` csv
COMMENT,name,description,series,,,,
META,S2,Supper Meter Device,v1,,,,
,,,,,,,
COMMENT,name,description,data address,vt,offset,rate,format
INPUT,total,组合有功总电能(kWh),0x00000000,,,,
INPUT,total_positive,正向有功总电能(kWh),0x00010000,,,,
INPUT,total_negative,反向有功总电能(kWh),0x00020000,,,,
INPUT,balance,剩余电量(kWh),0x00900100,,,,
INPUT,overdraft,透支电量(kWh),0x00900101,,,,
INPUT,current_total,当前结算周期组合有功总累计用电量(kWh),0x000B0000,,,,
,,,,,,,
COMMENT,name,description,data address,vt,rate,format,
OUTPUT,xxx,xxx,0x00000000,,,,
```



