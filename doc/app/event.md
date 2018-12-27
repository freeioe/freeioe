
----

# 事件类型和等级


### 等级

事件有以下等级:
``` lua
{
	LEVEL_DEBUG = 0,
	LEVEL_INFO = 1,
	LEVEL_WARNING = 2,
	LEVEL_ERROR = 3,
	LEVEL_FATAL = 99,
}
```

示例:

``` lua
local lvl = event.LEVEL_INFO
```


### 类型

事件有以下类型

```
{
	EVENT_SYS,
	EVENT_DEV,
	EVENT_COMM,
	EVENT_DATA,
	EVENT_APP,
}
```

示例:

``` lua
local type = event.EVENT_DATA
```


###  type_to_string
> function type_to_string(type)

事件类型转换函数:

* type: 事件类型（参考上述类型定义），也可以是自定义字符串


示例:

``` lua
print(event.type_to_string(event.LEVEL_INFO))
```

