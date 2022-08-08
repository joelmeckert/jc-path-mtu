# jc-path-mtu
Bash script to find the MTU of a remote host, outputs to JSON, conceptually designed for Zabbix or to run as a script on a monitoring server. It requires ICMP connectivity, jq, and jc. Sends JSON output to stdout, errors to stderr, expects jc to be located in /usr/local/bin/jc or /usr/bin/jc.

# Usage
```
./jc-path-mtu.sh contoso.com
./jc-path-mtu.sh contoso.com 1492
./jc-path-mtu.sh contoso.com 1500 0.2
./jc-path-mtu.sh contoso.com 1450 .05
./jc-path-mtu.sh 1.1.1.1
```
# Raw output
```
./jc-path-mtu.sh 1.1.1.1 | jq .mtu
```

# Dependencies
bash, jq, and jc
- https://github.com/stedolan/jq
- https://github.com/kellyjonbrazil/jc

# Notes
I had attempted to use nmap, but some providers block ICMP types other than echo requests. An MTU change anywhere in the path can destroy IPSec VPNs over UDP.
