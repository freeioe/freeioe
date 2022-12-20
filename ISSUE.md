# Issue List

1. Timestamp issue with NTP

The device may have incorrect time when starts FreeIOE, thus the skynet.time() will not be equal as os.time().  We had a fix for this issue, but it is not perfect solution.  We have to accept that as we do not want to restart FreeIOE.

2. Message queue may overload issue

In my own PC, the max data process ability is about 50000 data changes per second. This is up to CPU ability for detect data changes and the string compress speed.
