FreeIOE
===================

[FreeIOE](http://freeioe.org) 是用于构建智能的物联网数据网关的软件框架。

[English|英文](/README.md)


## 如何使用FreeIOE智能设备

[快速指南](https://help.cloud.thingsroot.com) 如果快速体验FreeIOE网关设备带来的极致体验，以及如果进行定制开发等等。

[冬笋云平台](http://cloud.thingsroot.com) FreeIOE默认使用的设备维护云平台。

[FreeIOE社区](http://freeioe.org) FreeIOE 开源社区.


## 应用开发相关文档

### 应用接口说明文档

[FreeIOE应用开发指南](https://srdgame.gitbooks.io/freeioe-app-api-book/content/) 应用开发接口说明，以及应用开发入门介绍等。


### 应用示例

[FreeIOE 应用示例代码库](https://github.com/freeioe/freeioe_example_apps)

此代码库包含一些示例应用，包含：

* Modbus 设备数据采集应用，基于lua-modbus模块(libmodbus)
* Modbus 设备数据采集应用(纯Lua实现)
* OpcUA 服务器/客户端示例(使用open62541协议栈)
* 基于Socat/Frpc 工具的网络/串口远程映射
* Aliyun/Huawei/Baidu 物联网平台接入 (基于MQTT协议)
* DLT645 电表数据采集应用(纯Lua实现)
* 基于uci指令的网络管理应用
* 基于OpcUA协议的SymLink数据集成应用


## FreeIOE核心开发文档

FreeIOE 基于 [Skynet] (https://github.com/cloudwu/skynet) 框架. 可以从 [Skynet Wiki](https://github.com/cloudwu/skynet/wiki) 获取更多信息。


## 提交代码问题

使用github的[问题列表](https://github.com/freeioe/freeioe/issues).


## 购买FreeIOE智能设备

[冬笋科技](https://thingsroot.com/product/)


## 已知问题

* FreeIOE upgradation will not remove original files.
> 1. the delete files from new package will retain in local
> 2. cannot have file(soft link file) replace directory
