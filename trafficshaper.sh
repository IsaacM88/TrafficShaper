#!/bin/sh

# Everything set by this script will reset to default when the computer restarts.

# Define variables
tcBin=`which tc` # Path to Traffic Control binary.
ipBin=`which ip` # Path to ip binary.
etBin=`which ethtool` # Path to ethtool binary.
upLimit=8mbit # Upload bandwidth limit.
downLimit=88mbit # Download bandwidth limit.
if=enp6s0 # Your network interface name. Use "ip address" command to get interfaces.
ifb=ifb0 # Incoming traffic will be redirected to this pseudo network interface.

# Load Modules
modprobe ifb
modprobe sch_fq_codel
modprobe act_mirred

# Display arguments to the user.
function halp {
	echo -e "\nArguments: trafficshaper.sh [OPTION]\n\
		\n\tstatus\tDisplay queuing disciplines attached to the network interfaces\
		\n\tstart\tStart shaping traffic\
		\n\tstop\tStop shaping traffic by deleting all queuing disciplines and subclasses\n"
}

# Display queuing disciplines attached to the network interfaces.
function status {
	echo -e "\n== Interface: $if ==\n"
	$tcBin -s qdisc show dev $if
	echo -e "\n== Interface: $ifb ==\n"
	$tcBin -s qdisc show dev $ifb
	echo ""
}

# Delete queuing disciplines and restore NIC offloading.
function stop {
	# Delete queuing disciplines, if they exist.
	netRules=`$tcBin qdisc show dev $if`
	if [[ "$netRules" == *"qdisc htb 1: root"* ]]; then
		$tcBin qdisc delete dev $if root; fi
	if [[ "$netRules" == *"qdisc ingress ffff: parent ffff:fff1"* ]]; then
		$tcBin qdisc delete dev $if ingress; fi

	ifbRules=`$tcBin qdisc show dev $ifb`
	if [[ "$ifbRules" == *"qdisc htb 1: root"* ]]; then
		$tcBin qdisc delete dev $ifb root; fi

	# Offload network processing to NIC instead of CPU.
	etConfig=`$etBin -k $if`
	if [[ "$etConfig" == *"tcp-segmentation-offload"* ]]; then
		$etBin -K $if tso on;	fi
	if [[ "$etConfig" == *"generic-segmentation-offload"* ]]; then
		$etBin -K $if gso on;	fi
	if [[ "$etConfig" == *"generic-receive-offload"* ]]; then
		$etBin -K $if gro on;	fi

	# Turn off the ifb interface
	$ipBin link set $ifb down
}

function start {
	# Delete existing queuing disciplines.
	stop

	# Make sure the traffic shaper is not bypassed.
	# These settings will offload network processing to the NIC when enabled.
	etConfig=`$etBin -k $if`
	if [[ "$etConfig" == *"tcp-segmentation-offload"* ]]; then
		$etBin -K $if tso off;	fi
	if [[ "$etConfig" == *"generic-segmentation-offload"* ]]; then
		$etBin -K $if gso off;	fi
	if [[ "$etConfig" == *"generic-receive-offload"* ]]; then
		$etBin -K $if gro off;	fi

	# Upload
	
	# Limit egress traffic using hbt and fq_codel.
	$tcBin qdisc add dev $if root handle 1: htb default 1
	$tcBin class add dev $if parent 1: classid 1:1 htb rate $upLimit
	$tcBin qdisc add dev $if parent 1:1 fq_codel

	# Download

	# Turn on the ifb interface.
	$ipBin link set $ifb up

	# Forward all incoming traffic to IFB where it will be rate limited.
	$tcBin qdisc add dev $if handle ffff: ingress
	$tcBin filter add dev $if parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev $ifb

	# Limit egress traffic for ifb using hbt and fq_codel.
	$tcBin qdisc add dev $ifb root handle 1: htb default 1
	$tcBin class add dev $ifb parent 1: classid 1:1 htb rate $downLimit
	$tcBin qdisc add dev $ifb parent 1:1 fq_codel
}

if [ "$1" == "status" ]; then status
elif [ "$1" == "stop" ]; then stop
elif [ "$1" == "start" ]; then start
else halp
fi