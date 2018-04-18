# 应用开发接口（DEVICE部分） #

* device:cleanup()

设备清理接口。

* device:mod(inputs, outputs, commands)

修改设备描述项。 参考api:create_device

* device:get_input_prop(input, prop)

获取设备输入项的当前值。

input: 输入项

prop: 输入项属性

* device:set_input_prop(input, prop, value, timestamp, quality)

写入设备输入项属性值。

input: 输入项

prop: 输入项属性。其中value是用于采集数据值。

value: 数据

timestamp: 时间戳。 默认为当前时间

quality: 质量戳。默认为0
```
dev:set_input_prop("Temperature", "value", 10)
```

* device:get_output_prop(output, prop)

获取设备输出项当前输出数据

* device:set_output_prop(output, prop, value)

写入输出项数据

* device:send_command(command, param)

发送设备控制指令

* device:list_props()

获取设备属性，包含inputs, outputs, commands

* device:dump_comm(dir, ...)

记录设备报文。 参考sys:dump_comm

* sys:fire_event(sn, level, data, timestamp)

记录应用事件。 参考sys:fire_event

* device:stat(name)

获取数据统计对象。参考app:stat
