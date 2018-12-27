
----

# 基础接口

FreeIOE框架为每个应用创建的服务接口，用以帮助应用快速构建设备模型等操作


### set_handler
> function api:set_handler(handler, watch_data)

设定处理函数。

* handler：接口对象
* watch_data: 是否关注其他应用创建的设备数据消息


> 示例:
```
local api = sys:data_api()
api:set_handler({
	on_comm = function(app, sn, ...) end, -- watch_data = true
	on_stat = function(app, sn, ...) end, -- watch_data = true
	on_input = function(...) end, -- watch_data = true
	on_add_device = function(...) end, -- watch_data = true
	on_del_device = function(...) end, -- watch_data = true
	on_mod_device = function(...) end, -- watch_data = true
	on_output = function(...) end, -- 数据输出项回调
	on_command = function(...) end, -- 命令回调
	on_ctrl = function(...) end, -- 应用控制接口
```


### list_devices
> function api:list_devices()

枚举系统中所有设备对象的描述信息 (meta, inputs, outputs, commands等等)


### add_device
> function api:add_device(sn, meta, inputs, outputs, commands)

创建新的采集设备对象。返回设备对象实例（参考[设备API](device.md))。

* sn：设备序列号
* meta: 设备Meta信息
* inputs：设备输入项列表
* outputs：设备输出项列表
* commands：设备控制项列表


### del_device
> function api:del_device(dev)

删除设备。 dev为设备对象实例。


### get_device
> function api:get_device(sn)

获取设备对象实例。 此接口对象只能用来读取设备输入项数据，写入设备输出项，发送设备控制项。


### send_ctrl
> function api:send_ctrl(app, ctrl, params)

发送应用控制指令。 会调用应用设定的handler.on_ctrl


### cleanup
> function api:cleanup()

接口清理接口（sys接口清理时，会自动调用此接口）

### api:\_dump_comm(sn, dir, ...)

*内部接口*


### api:\_fire_event(sn, level, data, timestamp)

*内部接口*
