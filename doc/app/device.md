---

# 设备接口

设备对象具备的接口列表


### mod
> function device:mod(inputs, outputs, commands)

修改设备描述项。 参考api:create_device

* inputs: 设备输入项
* outputs: 设备输出项
* commands: 设备指令


### add
> function device:add(inputs, outputs, commands)

在原有设备描述项基础上增加信息。 参考api:create_device


### get_input_prop
> function device:get_input_prop(input, prop)

获取设备输入项的当前值。

* input: 输入项名称
* prop: 输入项属性名称


### set_input_prop
> function device:set_input_prop(input, prop, value, timestamp, quality)

写入设备输入项属性值。

* input: 输入项
* prop: 输入项属性。其中value是用于采集数据值。
* value: 数据
* timestamp: 时间戳。 默认为当前时间
* quality: 质量戳。默认为0


> 示例:
```
dev:set_input_prop("Temperature", "value", 10)
```


### set_input_prop_emergency
> function device:set_input_prop_emergency(input, prop, value, timestamp, quality)

写入设备输入项属性值(紧急数据，需要尽快传递至云端数据)。
 
*此接口内部会调用set_input_prop接口，保证云端不处理紧急数据的情况下，也会将数据记录到云端。*

* input: 输入项名称
* prop: 属性名称
* value: 数据值
* timestamp: 时间戳
* quality: 质量戳


### get_output_prop
> function device:get_output_prop(output, prop)

获取设备输出项当前输出数据


### set_output_prop
> function device:set_output_prop(output, prop, value)

写入输出项数据


### send_command
> function device:send_command(command, param)

发送设备控制指令


### list_props
> function device:list_props()

获取设备属性，包含inputs, outputs, commands


### dump_comm
> function device:dump_comm(dir, ...)

记录设备报文。 参考sys:dump_comm


### fire_event
> function device:fire_event(level, type, info, data, timestamp)

记录设备事件。 参考sys:fire_event


### stat
> function device:stat(name)

获取数据统计对象。参考app:stat


### cleanup
> function device:cleanup()
设备清理接口。*此接口为内部接口，无需主动调用*。

