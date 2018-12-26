FreeIOE
===================

**[FreeIOE](http://freeioe.org)** 是用于快速构建物联网智能数据网关的开源框架。 [English|英文](/README.md)


## 如何使用

* [快速指南](https://help.cloud.thingsroot.com)  
如果快速体验FreeIOE网关设备带来的极致体验，以及如果进行定制开发等等。

* [冬笋云平台](http://cloud.thingsroot.com)  
FreeIOE默认使用的设备维护云平台。

[FreeIOE社区](http://freeioe.org)  
FreeIOE 开源社区.


## 应用开发

### 文档

* [FreeIOE 应用开发指南](https://freeioe.gitbook.io/doc/)  
应用开发接口说明，以及应用开发入门介绍等。


### 示例

* [FreeIOE 应用示例代码库](https://github.com/freeioe/freeioe_example_apps)  
包含：
  * Modbus 设备数据采集应用，基于lua-modbus模块(libmodbus)
  * Modbus 设备数据采集应用(纯Lua实现)
  * OpcUA 服务器/客户端示例(使用open62541协议栈)
  * 基于Socat/Frpc 工具的网络/串口远程映射
  * Aliyun/Huawei/Baidu 物联网平台接入 (基于MQTT协议)
  * DLT645 电表数据采集应用(纯Lua实现)
  * 基于uci指令的网络管理应用
  * 基于OpcUA协议的SymLink数据集成应用
  * 发那科Focas协议数据采集(通过ubus服务)


## 核心开发

FreeIOE 基于 [Skynet] (https://github.com/cloudwu/skynet) 框架.
> 可以从它的[wiki](https://github.com/cloudwu/skynet/wiki) 获取更多信息。


## 提交问题

请使用github的[问题列表](https://github.com/freeioe/freeioe/issues).


## 购买FreeIOE 物联网智能网关

* 冬笋科技: [ThingsLink系列](https://www.thingsroot.com/product/)
* 旋思科技: [SymLink系列](http://www.symid.com/)


## 已知问题

* FreeIOE 新版本中有文件被移除，在升级时并未移除本地文件.
> 1. 本地遗留有之前版本的一些文件，在新版中这些文件已经被删除
> 2. 同名目录不能被文件或者软链接替换

## 授权协议

MIT
