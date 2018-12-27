FreeIOE
===================

**[FreeIOE](http://freeioe.org)** is a framework for building IOE (Internet Of Everything) gateway device. [Chinese|中文](/README_CN.md)


## How To Use

* [Guick Guide](https://help.cloud.thingsroot.com)  
Quick start guide (only in Chinese for now)

* [ThingsRoot Cloud](http://cloud.thingsroot.com)  
The default cloud provider for FreeIOE

* [FreeIOE forum](http://freeioe.org)  
The discussion forum


## App Development

### Documents

* [FreeIOE Application Guide](https://freeioe.gitbook.io/doc/)


### Examples

* [Example Applications](https://github.com/freeioe/freeioe_example_apps)  
Includes:
  * Modbus application with lua-modbus(libmodbus)
  * Modbus application implemented in pure lua
  * OpcUA Server/Client applications
  * Socat/Frpc utils control applications
  * Aliyun/Huawei/Baidu IOT cloud application (based on MQTT)
  * DLT645 application implemented in pure lua
  * Device network configuration application (based on uci)
  * SymLink connector with OpcUA
  * Fanuc Focas CNC connector via ubus broker


## Core Development

FreeIOE is based on [Skynet](https://github.com/cloudwu/skynet) framework.
> More information can be found in its [wiki](https://github.com/cloudwu/skynet/wiki)
> FreeIOE works with on [skynet](https://github.com/srdgame/skynet) with a few more lua C modules


## Report Issues

Please use [issue list](https://github.com/freeioe/freeioe/issues).


## Where To Buy 

* [ThingsLink](https://www.thingsroot.com/product/)
* [SymLink](http://www.symid.com/)


## Known Issue

* FreeIOE upgradation will not remove original files.
> 1. the delete files from new package will retain in local
> 2. cannot have file(soft link file) replace directory

## LICENSE

MIT
