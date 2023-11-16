# FreeIOE

**[FreeIOE](http://freeioe.org)** 是用于快速构建工业物联网边缘计算网关的开源框架。 [English|英文](/README.md)

## 如何使用

* [FreeIOE WIKI 知识库](https://wiki.freeioe.org)
* [FreeIOE 配套云平台](https://wiki.freeioe.org/cloud/index)

## 应用开发

### 文档

* [FreeIOE 应用开发手册](https://freeioe.gitbook.io/doc/)

### 示例

* [FreeIOE 应用示例代码库](https://github.com/freeioe/freeioe_example_apps)
  * Modbus 应用示例（Master/Slave)
  * OPCUA 应用示例(Server/Client)
  * 发那科Focas协议数据采集(通过ubus服务)
  * DLT645 电表数据采集应用
  * Aliyun/Huawei/Baidu/联通云(Telit)/浪潮云/中信云 等物联网平台接入 (基于MQTT协议)
  * 基于Socat/Frpc 工具的网络/串口远程映射
  * 基于uci指令的网络管理应用
  * 支持支持EtherNet/IP CIP协议的PLC接入示例
  * 三菱MC协议PLC接入示例
  * 欧姆龙Hostlink协议接入示例
  * 时序数据库写入示例

* [FreeIOE 应用示例 #2](https://github.com/viccom/myfreeioe_apps)
  * 支持设备点表的Modbus数据采集应用
  * 华为UPS2000设备数据采集应用（基于Modbus)
  * 华为UPS2000数据导出到Redis数据库
  * 设备多路由管理应用（自动切换4G和有线网络)
  * 网管网络信息收集应用
  * 网络、串口远程映射应用
  * 西门子PLC S7全系列应用
  * 设备远程编程应用（网络设备、串口设备)
  * MQTT数据上送示例
  * 华日激光数据采集应用（主动模式)

## 框架开发

FreeIOE 基于 [Skynet] (https://github.com/cloudwu/skynet) 框架.

> 可以从它的[wiki](https://github.com/cloudwu/skynet/wiki) 获取更多信息。
> FreeIOE使用的[skynet](https://github.com/srdgame/skynet) 具有更多的C扩展模块

## 提交问题

请使用github的[问题列表](https://github.com/freeioe/freeioe/issues).

## 购买FreeIOE 物联网智能网关

* [支持的硬件列表](https://wiki.freeioe.org/hardwares/start)

## 已知问题

## 授权协议

MIT
