#!/bin/bash
# Joel Eckert, joel@joelme.ca, 2022-07-19

# Usage:
# ./jc-path-mtu.sh contoso.com
# ./jc-path-mtu.sh contoso.com 1492
# ./jc-path-mtu.sh contoso.com 1500 0.2
# ./jc-path-mtu.sh contoso.com 1450 .05

# Adjust the maxmtu, minmtu, and ICMP timeout as required for higher latency links, default is 0.1, 100 ms
maxmtu=1500
minmtu=500
overhead=28
rx_timeout='^([0-9]?)(\.([0-9])?|\.[0-9][0-9]?)$'

# If 3rd timeout argument is specified, validate it with regex, set the default upon failure
if [[ -z "${3}" ]]; then
	timeout=0.1
else
	if [[ $3 =~ $rx_timeout ]]; then
		timeout=$3
	else
		timeout=0.1
	fi
fi

# Validate that the specifid MTU is a maximum of four numeric integers
rx_mtu='^[0-9]{3,4}$'

remote="${1}"
jcpath="/usr/local/bin/jc"
jcpath2="/usr/local/bin/jc"
jcuri='https://github.com/kellyjonbrazil/jc'
jqpath="/usr/bin/jq"
jquri='https://github.com/stedolan/jq'

# Test to determine that jc is installed to parse the ping output, then determine if the host is reachable with ICMP
if [[ -f "${jcpath}" ]] && [[ -f "${jqpath}" ]]; then
	# Determine if the remote host is responsive, useful for validating input
	respond=$(ping -c 1 "${remote}" -W $timeout | jc --ping -p | jq .packets_received)
else
	# Output to stderr
	if [[ ! -f "${jcpath}" ]]; then
		if [[ -f "${jcpath2}" ]]; then
			jcpath="${jcpath2}"
		else
			echo -e "\e[31m\e[1mERROR: \e[37mjc not found at ${jcpath}\n\e[34m\e[4m${jcuri}\e[0m" >&2
		fi
	fi
	if [[ ! -f "${jqpath}" ]]; then
		echo -e "\e[31m\e[1mERROR: \e[37mjq not found at ${jqpath}\n\e[34m\e[4m${jquri}\e[0m" >&2
	fi
fi

# If the host responds to ICMP, proceed with the tests
if [[ $respond -gt 0 ]]; then

	# If MTU is specified as the second argument, calculate overhead, if not specified, calculate overhead based on max MTU
	if [[ ! -z $2 ]] && [[ $2 =~ $rx_mtu ]] && [[ $2 < $maxmtu ]]; then
		icmpsize=$(($2 - $overhead))
	else
		icmpsize=$(($maxmtu - $overhead))
	fi
	
	# Set packet loss to 100%
	results=100
	
	# Loop until there is an ICMP response, decrementing by one byte each loop where required
	while [[ $results -gt 0 ]] && [[ $icmpsize -ge $minmtu ]]; do
		results=$(ping -c 1 -M do -s $icmpsize -W $timeout "${remote}" | jc --ping -p | jq .packet_loss_percent)
		# If there is more than 0% packet loss, decrement by one byte
		if [[ $results > 0 ]]; then
			icmpsize=$(($icmpsize - 1))
		fi
	done
	
	# Calculate MTU from ICMP size
	mtu=$(($icmpsize + $overhead))
	json=$(echo -e '{'"\n"'  "mtu": '"${mtu}\n"'}'"\n")
	echo $json | jq

else
	
	# Output error to stderr, failed to discover MTU
	echo -e "\e[31m\e[1mERROR: \e[37mMTU discovery failed, ICMP echo reply blocked or hostname / IP is invalid.\e[0m" >&2

	# Return a zero integer value for the MTU
	json=$(echo -e '{'"\n"'  "mtu": 0'"\n"'}'"\n")
	if [[ -f "${jqpath}" ]]; then
		echo $json | jq
	else
		echo -e $json
	fi
fi
