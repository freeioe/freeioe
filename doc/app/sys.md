
---

# 系统接口

FreeIOE框架提供的系统类型接口。


### log
> function sys:log(level, ...)

记录应用日志。 level是字符串类型，可用值:trace, debug, info, notice, warning, error, fatal.

```
sys:log("debug", "this is a log content")
```


### logger
> function sys:logger()

获取logger实例。 实例包含:trace, debug, info, notice, warning, error, fatal. 例如:

```
local log = sys:logger()
log:debug("this is a log content")
```


### dump_comm
> function sys:dump_comm(sn, dir, ...)

记录应用报文。 sn是应用创建的设备序列号/为空时代表设备无关报文。参考[device](device.md) 中的[dump_comm](device.md#dump_comm)函数。 dir是报文方向： IN, OUT。


### fire_event
> function sys:fire_event(sn, level, type, info, data, timestamp)

记录应用事件。 sn是应用创建的设备序列号。level是事件等级的整数,type是事件类型(如果是字符串类型则是自定义类型),info是事件描述字符串,data是时间附带数据,timestamp是时间戳。


### fork
> function sys:fork(func, ...)

创建独立携程,入口执行函数func. 后面是变参参数。

```
sys:fork(function(a)
	print(a)
end, 1)
```

其中a是传入的参数1


### timeout
> function sys:timeout(ms, func)

创建延迟执行携程, ms为延迟时间（单位是毫秒）, func为携程入口函数。


### cancelable_timeout
> function sys:cancelable_timeout(ms, func)

创建可以取消的延迟携程，返回对象是取消函数

```
local timer_cancel = sys:cancelable_timeout(...)
timer_cancel()
```


### exit
> function sys:exit()

应用退出接口。请谨慎使用。 


### abort
> function sys:abort()

系统退出接口，调用此接口会导致FreeIOE系统退出。 请谨慎调用。 


### now
> function sys:now()

返回操作系统启动后的时间计数。 单位是微妙，最小有效精度是10毫秒。


### time
> function sys:time()

获取系统时间，单位是秒，并包含两位小数的毫秒。


### start_time
> function sys:start_time()

系统启动的UTC时间，单位是秒。


### yield
> function sys:yield()

交出当前应用对CPU的控制权。相当与sys:sleep(0)。


### sleep
> function sys:sleep(ms)

挂起当前应用， ms是挂起时常，单位是毫秒


### data_api
> function sys:data_api()

获取数据接口，参考[api](api.md)


### self_co
> function sys:self_co()

获取当前运行的携程对象


### wait
> function sys:wait()

挂起当前携程，结合sys:wakeup使用


### wakeup
> function sys:wakeup(co)

唤醒一个被sys:sleep或sys:wait挂起的携程。


### app_dir
> function sys:app_dir()

获取当前应用所在的目录。


### app_sn
> function sys:app_sn()

获取当前应用的序列号。


### get_conf
> function sys:get_conf(default_config)

获取应用配置，default_config默认配置


### set_conf
> function sys:set_conf(config)

设定应用配置


### conf_api
> function sys:conf_api(conf_name, ext, dir)

获取云配置服务接口。 具体参考[conf_api](conf_api.md)


### version
> function sys:version()

获取应用版本号。返回应用ID和应用版本

```
local app_id, version = sys:version()
print(app_id, version)
```


### gen_sn
> function sys:gen_sn(dev_name)

生成独立的设备序列号，dev_name为设备名称，必须指定。


### hw_id
> function sys:hw_id()

获取FreeIOE设备序列号


### id
> function sys:id()

获取FreeIOE连接云平台所用的序列号(此ID可不同与设备序列号)


### req
> function sys:req(msg, ...)

发送同步请求，相应函数为app.response或者app.on_req_<msg>函数


### post
> function sys:post(msg, ...)

发送异步请求，相应函数为app.accept或者app.on_post_<msg>函数


### cleanup
> function sys:cleanup()

应用清理接口(会自动被调用，请勿使用)


