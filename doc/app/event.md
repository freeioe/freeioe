事件等级：

```
{
	LEVEL_DEBUG = 0,
	LEVEL_INFO = 1,
	LEVEL_WARNING = 2,
	LEVEL_ERROR = 3,
	LEVEL_FATAL = 99,
}
```

事件类型：

```
{
	EVENT_SYS,
	EVENT_DEV,
	EVENT_COMM,
	EVENT_DATA,
	EVENT_APP,
}
```

事件类型转换函数:

* type\_to\_string\(type\)

type:事件类型（参考上述类型定义），也可以是自定义字符串





