FreeIOE
===================

**[FreeIOE](http://freeioe.org)** is a framework for building IOE (Internet Of Everything) gateway device. [Chinese|中文](/README_CN.md)


## How To Use

* [Guick Guide](http://help.cloud.thingsroot.com/quick_start/)\
	Quick start guide (only in Chinese for now)

* [ThingsRoot Cloud](http://cloud.thingsroot.com)\
	The default cloud provider for FreeIOE

* [FreeIOE forum](http://freeioe.org)\
	The discussion forum


## App Development

### Documents

* [FreeIOE Application Guide](https://freeioe.gitbook.io/doc/)
	FreeIOE application development guide


### Examples

* [Example Applications](https://github.com/freeioe/freeioe_example_apps)
  * Modbus data collect application with lua-modbus(libmodbus)
  * Modbus data collect application implemented in pure lua
  * OpcUA Server/Client data provider applications
  * Socat/Frpc utils control applications
  * Aliyun/Huawei/Baidu IOT cloud connector (based on MQTT)
  * DLT645 device data collection application implemented in pure lua
  * Device network configuration collection application (based on uci)
  * SymLink connector with OpcUA
  * Fanuc Focas CNC device data collection via ubus broker
  * Telit cloud integration application
  * Yizumi UN200A5 data collection application (via OpcUa)
  * Citic cloud integration application

* [Thirdparty Applications](https://github.com/viccom/myfreeioe_apps)
  * Modbus device data collection application with device template support
  * Huawei UPS2000 data collection application (based on modbus)
  * Huawei UPS2000 data to redis application
  * Multiple gateway route management (auto switch ethernet and 4G link)
  * Gateway network information collect application
  * Netowork/Serial remote mapping application
  * Semens S7 PLC connector (based on snap7 library)
  * Device remote connect applications (Serial & Network)
  * MQTT data upload application demo
  * Huaraylaser 355 device connector


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
