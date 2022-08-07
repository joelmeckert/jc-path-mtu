#!/bin/bash
# Joel Eckert, joel@joelme.ca, 2022-08-07

# Usage, JSON output:
# ./jc-path-mtu.sh contoso.com
# ./jc-path-mtu.sh contoso.com 1492
# ./jc-path-mtu.sh contoso.com 1500 0.2
# ./jc-path-mtu.sh contoso.com 1450 .05

# Usage, example with jq returning integer
# ./jc-path-mtu.sh contoso.com | jq .mtu

# Adjust the maximum and minimum MTU, and ICMP timeout as required for higher latency links, default is 0.1, 100 ms
mtu_maximum=1500
mtu_minimum=500
overhead=28
bytes_minimum=$(( $mtu_minimum + $overhead ))
timeout_default=0.1
rx_timeout='^([0-9]?)?(\.([0-9])?|\.[0-9][2-9]?)$'

# If 3rd timeout argument is specified, validate it with regex, set the default upon failure
if [[ "${3}" =~ $rx_timeout ]]; then
	timeout=$3
else
	timeout=$timeout_default
fi

# Validate that the specifid MTU is a maximum of 1500
rx_mtu='^(([1][0-4][0-9]{2})|([1-9][0-9]{2}))$'

# Remote host
host="${1}"

# Link to jc and jq on GitHub
jcuri='https://github.com/kellyjonbrazil/jc'
jquri='https://github.com/stedolan/jq'
jc_path_mtu="https://github.com/joelmeckert/jc-path-mtu"

# Determines the location of jc, if it exists, sets the path to the jqpath variable
jcpath=$(which jc)
if [[ $? -ne 0 ]]; then
	echo -e "\e[31m\e[1mERROR\t\e[0mjc not found\e[1m\t\e[34m\e[4m${jcuri}\e[0m" >&2
	exitflag=1
fi

# Determines the location of jq, if it exists, sets the path to the jqpath variable
jqpath=$(which jq)
if [[ $? -ne 0 ]]; then
	echo -e "\e[31m\e[1mERROR\t\e[0mjq not found\e[1m\t\e[34m\e[4m${jquri}\e[0m" >&2
	exitflag=1
fi

if [[ $exitflag -eq 1 ]]; then
	echo -e "\t\e[1mjc-path-mtu\t\e[1m\e[34m\e[4m${jc_path_mtu}\e[0m" >&2
	exit 1
fi

# Determine if the host is reachable via ICMP
attempts=2
bytes_test=56
result=$(ping -c $attempts -M do -s $bytes_test -W $timeout "${host}" | jc --ping -p | jq)
egress=$(echo "${result}" | jq .packets_transmitted)
ingress=$(echo "${result}" | jq .packets_received)
lost=$(($egress - $ingress))

# If MTU is specified as the second argument, calculate overhead, if not specified, calculate overhead based on max MTU
if [[ "${2}" =~ $rx_mtu ]]; then
	bytes=$(($2 - $overhead))
else
	bytes=$(($mtu_maximum - $overhead))
fi

# If the host responds to ICMP, proceed with the tests
if [[ $lost -eq 0 ]]; then
	
	# Set packets lost to 1
	lost=1
	
	# Loop until there is an ICMP response, decrementing by one byte each loop where required
	while [[ $lost -gt 0 ]] && [[ $bytes -ge $bytes_minimum ]]; do
	
		attempts=1
		result=$(ping -c $attempts -M do -s $bytes -W $timeout "${host}" | jc --ping -p | jq)
		egress=$(echo "${result}" | jq .packets_transmitted)
		ingress=$(echo "${result}" | jq .packets_received)
		lost=$(($egress - $ingress))

		# If there is packet loss, decrement by one byte
		if [[ $lost -gt 0 ]]; then
			bytes=$(($bytes - 1))
		
		# If single echo is successful, test for two echo replies, packet loss should be zero
		else
			attempts=2
			result=$(ping -c $attempts -M do -s $bytes -W $timeout "${host}" | jc --ping -p | jq)
			egress=$(echo "${result}" | jq .packets_transmitted)
			ingress=$(echo "${result}" | jq .packets_received)
			lost=$(($egress - $ingress))

			# If there is packet loss, decrement by one byte
			if [[ $lost -gt 0 ]]; then
				bytes=$(($bytes - 1))
			else
				success=1
				# Set the epoch variable to document the epoch seconds upon a successful test
				epoch=$EPOCHSECONDS
			fi
		fi
		
	done
fi

# If successful above, calculate the MTU, if it failed, return a zero integer value
if [[ $success -eq 1 ]]; then
	# Calculate MTU from ICMP size
	mtu=$(($bytes + $overhead))
else
	epoch=$EPOCHSECONDS
	mtu=0
	exitflag=1
	# Output error to stderr, failed to discover MTU
	echo -e "\e[31m\e[1mFAILED\e[0m\tMTU could not be reliably determined:\t${host}\e[0m" >&2
fi

# Set datetime variable from epoch seconds, ISO 8601
datetime=$(date -d @$epoch +"%Y-%m-%dT%T%:z")

# Create JSON
json=$(echo -e '{'"\n\t"'"date": "'$datetime'"'",\n\t"'"host": "'$host'"'",\n\t"'"mtu": '"$mtu,\n\t"'"timeout": '"$timeout,\n\t"'"epoch": '"$epoch\n"'}'"\n")

# Output to stdout via jq
echo "${json}" | jq

if [[ $exitflag -eq 1 ]]; then
	exit 1
fi
