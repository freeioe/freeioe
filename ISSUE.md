# Issue List

1. Timestamp issue with NTP

The device may have incorrect time when starts FreeIOE, thus the skynet.time() will not be equal as os.time().  We had a fix for this issue, but it is not perfect solution.  We have to accept that as we do not want to restart FreeIOE.
