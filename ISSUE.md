ISSUES
===================

# Issue List

1. popen hangs FreeIOE

 After started the process-monitor to watching frpc, the os.execute('cat /proc/loadavg') will be blocked.\
 The shell started by os.execute is in Z status in ps list. (it was happened in openwrt x86_64 image with vmware)
 > It is a bug of musl, waiting for musl 1.1.21 release.
 > issue [here](https://www.openwall.com/lists/musl/2018/11/02/1)

2. fix_time in skynet
 Once the ntp got new time, the skynet.time() will not be equal as os.time(). So we have an fix_time in skynet.\
 But the code seems not works well in VMWare boxes.
