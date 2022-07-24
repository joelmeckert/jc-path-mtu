#!/bin/bash
# Joel Eckert, joel@joelme.ca, 2022-07-20

# Usage:
# ./jc-path-mtu.sh contoso.com
# ./jc-path-mtu.sh contoso.com 1492
# ./jc-path-mtu.sh contoso.com 1500 0.2
# ./jc-path-mtu.sh contoso.com 1450 .05

# Adjust the maximum and minimum MTU, and ICMP timeout as required for higher latency links, default is 0.1, 100 ms
mtu_maximum=1500
mtu_minimum=500
overhead=28
bytes_minimum=$(( $mtu_minimum + $overhead ))
timeout_minimum=0.02
timeout_default=0.1
rx_timeout='^([0-9]?)?(\.([0-9])?|\.[0-9][0-9]?)$'

# If 3rd timeout argument is specified, validate it with regex, set the default upon failure
if [[ -z "${3}" ]]; then
	timeout=$timeout_default
else
	if [[ $3 =~ $rx_timeout ]]; then
		if [[ $3 > $timeout_minimum ]]; then
			timeout=$3
		else
			timeout=$timeout_minimum
		fi
	else
		timeout=$timeout_default
	fi
fi

# Validate that the specifid MTU is a maximum of four numeric integers
rx_mtu='^[0-9]{3,4}$'

# Remote host
host="${1}"

# Determines the location of jq, if it exists, sets the path to the jqpath variable
if [[ -f "${jqsearchpath1}" ]]; then
	jqpath="${jqsearchpath1}"
fi
if [[ -f "${jqsearchpath2}" ]]; then
	jqpath="${jqsearchpath2}"
fi

jcpath=$(which jc)
jqpath=$(which jq)

# Test to determine that jc and jq are installed to parse the ping output, then determine if the host is reachable
if [[ -f "${jcpath}" ]] && [[ -f "${jqpath}" ]]; then
	# Determine if the remote host is reachable via ICMP, useful for validating host input
	attempts=2
	bytes=56
	result=$(ping -c $attempts -M do -s $bytes -W $timeout "${host}" | jc --ping -p | jq)
	egress=$(echo "${result}" | jq .packets_transmitted)
	ingress=$(echo "${result}" | jq .packets_received)
	lost=$(($egress - $ingress))
else
	# Output to stderr if jc and jq do not exist
	if [[ ! -f "${jcpath}" ]]; then
		echo -e "\e[31m\e[1mERROR\e[0m\t\e[4mjc not found\e[0m at \e[1m${jcsearchpath1}\e[0m \e[33mor\e[0m \e[1m${jcsearchpath2}\e[0m\n\e[1mLink\t\e[34m\e[4m${jcuri}\e[0m" >&2
	fi
	if [[ ! -f "${jqpath}" ]]; then
		echo -e "\e[31m\e[1mERROR\e[0m\t\e[4mjq not found\e[0m at \e[1m${jqsearchpath1}\e[0m \e[33mor\e[0m \e[1m${jqsearchpath2}\e[0m\n\e[1mLink\t\e[34m\e[4m${jquri}\e[0m" >&2
	fi
fi

# If the host responds to ICMP, proceed with the tests
if [[ $lost == 0 ]]; then

	# If MTU is specified as the second argument, calculate overhead, if not specified, calculate overhead based on max MTU
	if [[ -n $2 ]] && [[ $2 =~ $rx_mtu ]] && [[ $2 < $mtu_maximum ]]; then
		bytes=$(($2 - $overhead))
	else
		bytes=$(($mtu_maximum - $overhead))
	fi

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

	# If successful above, calculate the MTU, if it failed, return a zero integer value
	if [[ $success -eq 1 ]]; then
		# Calculate MTU from ICMP size
		mtu=$(($bytes + $overhead))
	else
		# Output error to stderr, failed to discover MTU
		echo -e "\e[31m\e[1mFAILED\e[0m\tMTU could not be reliably determined:\t${host}\e[0m" >&2
	fi

# Output error to stderr, failed to discover MTU, if jcpath and jqpath exist and processing could continue
else

	if [[ -f "${jcpath}" ]] && [[ -f "${jqpath}" ]]; then
		echo -e "\e[31m\e[1mERROR\e[0m\tMTU discovery failed for host, ICMP echo reply blocked or address is invalid:\t${host}\e[0m" >&2
	fi

fi

# If the epoch variable is not set, as the test was not successful, set it now
if [[ -z $epoch ]]; then
	epoch=$EPOCHSECONDS
	# Return a zero integer value for the MTU, so that the data returns an integer and not a null value for the monitoring system
	mtu=0
fi

datetime=$(date -d @$epoch +"%Y-%m-%dT%T%:z")

# Create JSON
json=$(echo -e '{'"\n\t"'"date": "'$datetime'"'",\n\t"'"host": "'$host'"'",\n\t"'"mtu": '"$mtu,\n\t"'"timeout": '"$timeout,\n\t"'"epoch": '"$epoch\n"'}'"\n")

# Output to stdout via jq
if [[ -f "${jqpath}" ]]; then
	echo "${json}" | jq
# Output to stdout, jq missing
else
	echo -e "${json}"
fi
