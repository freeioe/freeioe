# FreeIOE

**[FreeIOE](http://freeioe.org)** is an open source edge-computing framework for Industrial Internet of Things. [Chinese|中文](/README_CN.md)

## How To Use

* [FreeIOE wiki](http://wiki.freeioe.org)
* [FreeIOE Cloud](https://wiki.freeioe.org/cloud/index)

## App Development

### Documents

* [FreeIOE Application Development Book](https://freeioe.gitbook.io/doc/)

### Examples

* [Example Applications](https://github.com/freeioe/freeioe_example_apps)
  * Modbus application (Master/Slave)
  * OpcUA applications (Server/Client)
  * Fanuc Focas CNC device data collection via ubus broker
  * DLT645 device data collection application
  * Aliyun/Huawei/Baidu/Citic/Inspur/Telit/WeLink IOT Cloud connector
  * Socat/Frpc utils control applications
  * Device network configuration collection application (based on uci)
  * EtherNet/IP CIP protocol based PLC
  * Melsec protocol based PLC
  * AB-PLC based on libplctag
  * Omron PLC based on hostlink protocol
  * Time-series database writer

* [Thirdparty Applications](https://github.com/viccom/myfreeioe_apps)
  * Modbus device data collection application with device template support
  * Huawei UPS2000 data collection application (based on modbus)
  * Huawei UPS2000 data to redis application
  * Multiple gateway route management (auto switch ethernet and 4G link)
  * Gateway network information collect application
  * Network/Serial remote mapping application
  * Semens S7 PLC connector (based on snap7 library)
  * Device remote connect applications (Serial & Network)
  * MQTT data upload application demo
  * Huaray laser 355 device connector

## Core Development

FreeIOE is based on [Skynet](https://github.com/cloudwu/skynet) framework.

> More information can be found in its [wiki](https://github.com/cloudwu/skynet/wiki)
> FreeIOE works with on [skynet](https://github.com/srdgame/skynet) with a few more lua C modules

## Report Issues

Please use [issue list](https://github.com/freeioe/freeioe/issues).

## Where To Buy

* [Hardwares](https://wiki.freeioe.org/hardwares/start)

## Known Issue

## LICENSE

MIT
