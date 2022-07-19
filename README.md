# jc-path-mtu
Find MTU, requires ICMP and jc package. I had attempted to use nmap, but some providers block ICMP types other than echo requests.

# Usage:
./jc-path-mtu.sh contoso.com
./jc-path-mtu.sh contoso.com 1492
./jc-path-mtu.sh contoso.com 1500 0.2
./jc-path-mtu.sh contoso.com 1450 .05

# Dependencies:
https://github.com/kellyjonbrazil/jc
