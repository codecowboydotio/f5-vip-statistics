# f5-vip-statistics
F5 VIP statistics with differences between multiple runs

This script is a powershell script for F5 BIGIP devices.
It checks LTM virtual servers for statistics.
In this case it checks for total number of connections.
If run twice, the script calculates the difference between the first and second run, and creates and HTML file.

This is useful for knowing which VIPs are not being used.

The script requires the powershell iControl SDK to be installed to work.
