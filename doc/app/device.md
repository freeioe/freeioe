# 应用开发接口（DEVICE部分）

* device:cleanup\(\)

设备清理接口。

* device:mod\(inputs, outputs, commands\)

修改设备描述项。 参考api:create\_device

* device:add\(inputs, outputs, commands\)

在原有设备描述项基础上增加信息。 参考api:create_device

* device:get\_input\_prop\(input, prop\)

获取设备输入项的当前值。

input: 输入项

prop: 输入项属性

* device:set\_input\_prop\(input, prop, value, timestamp, quality\)

写入设备输入项属性值。

input: 输入项

prop: 输入项属性。其中value是用于采集数据值。

value: 数据

timestamp: 时间戳。 默认为当前时间

quality: 质量戳。默认为0

```
dev:set_input_prop("Temperature", "value", 10)
```

* device:set\_input\_prop\_emergency\(input, prop, value, timestamp, quality\)

写入设备输入项属性值(紧急数据，需要尽快传递至云端数据)。此接口内部会调用set_input_prop接口，保证云端不处理紧急数据的情况下，也会将数据记录到云端。

* device:get\_output\_prop\(output, prop\)

获取设备输出项当前输出数据

* device:set\_output\_prop\(output, prop, value\)

写入输出项数据

* device:send\_command\(command, param\)

发送设备控制指令

* device:list\_props\(\)

获取设备属性，包含inputs, outputs, commands

* device:dump\_comm\(dir, ...\)

记录设备报文。 参考sys:dump\_comm

* device:fire\_event\(level, type, info, data, timestamp\)

记录设备事件。 参考sys:fire\_event

* device:stat\(name\)

获取数据统计对象。参考app:stat

