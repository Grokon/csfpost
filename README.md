# csfpost
csfpost.sh dor docker with bridge


### Script to prepare and restore full docker iptables rules.

(C)2018 Owen Grok Yon
This script is provided as-is; no liability can be accepted for use.
You are free to modify and reproduce so long as this attribution is preserved.

Make sure to disable Docker's iptables management with --iptables=false.
CSF needs to be restarted whenever you make structural changes to Docker such as your networks, bridges or IP configuration.  
Or restart csf after rescreate conpose.
