ISSUES
===================

# Issue List

1. popen hangs FreeIOE  
 After started the process-monitor to watching frpc, the os.execute('cat /proc/loadavg') will be blocked.   
 The shell started by os.execute is in Z status in ps list. (it was happened in openwrt x86_64 image with vmware)
 > It is a bug of musl, waiting for musl 1.1.21 release.
 > issue [here](https://www.openwall.com/lists/musl/2018/11/02/1)
2. 
