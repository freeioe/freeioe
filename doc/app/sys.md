# 应用开发接口(SYS部分) #

* sys:log(level, ...)

记录应用日志。 level是字符串类型，可用值:trace, debug, info, notice, warning, error, fatal.
```
sys:log("debug", "this is a log content")
```

* sys:logger()

获取logger实例。 实例包含:trace, debug, info, notice, warning, error, fatal. 例如: 
```
local log = sys:logger()
log:debug("this is a log content")
```

* sys:dump_comm(sn, dir, ...)

记录应用报文。 sn是应用创建的设备序列号/为空时代表设备无关报文。参考api:create_device()函数。 dir是报文方向： IN, OUT。

* sys:fire_event(sn, level, data, timestamp)

记录应用事件。 sn是应用创建的设备序列号/为空时代表应用时间。level是事件等级的数字，data最少包含一个type的字段的table

* sys:fork(func, ...)

创建独立携程,入口执行函数func. 后面是变参参数。
```
sys:fork(function(a)
	print(a)
end, 1)
```
其中a是传入的参数1

* sys:timeout(ms, func)

创建延迟执行携程, ms为延迟时间（单位是毫秒）, func为携程入口函数。

* sys:cancelable_timeout(ms, func)

创建可以取消的延迟携程，返回对象是取消函数
```
local timer_cancel = sys:cancelable_timeout(...)
timer_cancel()
```

* sys:exit()

应用退出接口（特殊应用使用）

* sys:abort()

系统退出接口，调用此接口会导致IOT系统退出。 请谨慎调用。 

* sys:now()

返回操作系统启动后的时间计数。 单位是微妙，最小有效精度是10毫秒。

* sys:time()

获取系统时间，单位是秒，并包含两位小数的毫秒。

* sys:start_time()

系统启动的UTC时间，单位是秒。

* sys:yield()

交出当前应用对CPU的控制权。相当与sys:sleep(0)。

* sys:sleep(ms)

挂起当前应用， ms是挂起时常，单位是毫秒

* sys:data_api()

获取数据接口，参考app:api

* sys:self_co()

获取当前运行的携程对象

* sys:wait()

挂起当前携程，结合sys:wakeup使用

* sys:wakeup(co)

唤醒一个被sys:sleep或sys:wait挂起的携程。

* sys:app_dir()

获取当前应用所在的目录。

* sys:app_sn()

获取当前应用的序列号。

* sys:get_conf(default_config)

获取应用配置，default_config默认配置

* sys:set_conf(config)

设定应用配置

* sys:version()

获取应用版本号

* sys:gen_sn(dev_name)

生成独立的设备序列号，dev_name为设备名称，必须指定。

* sys:id()

获取IOT设备学列号

* sys:cleanup()

应用清理接口


