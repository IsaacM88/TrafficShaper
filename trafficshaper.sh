#!/usr/bin/bash

# User defined variables.
upLimit="8mibit" # Upload bandwidth limit.
downLimit="88mibit" # Download bandwidth limit.
if="enp6s0" # Your network interface name. Run "ip link show" to get interfaces.

# Default variables.
ifb="ifb0" # Incoming traffic will be redirected to this pseudo network interface.
suffixes=("" "bit" "Kibit" "kbit" "mibit" "mbit" "gibit" "gbit" "tibit" "tbit" "Bps" "KiBps" "KBps" "MiBps" "MBps" "GiBps" "GBps" "TiBps" "TBps")

# Load Modules
modprobe ifb
modprobe sch_fq_codel
modprobe act_mirred

# Check for proper upload and download limit formatting.
function checkLimit {
	[[ "$1" =~ ^[[:digit:]]+.*$ && " ${suffixes[@]} " =~ " ${1//[[:digit:][:punct:]]/} " ]] || { echo "1"; return; }
}

# Check for valid variables.
function check {
	[[ -z $(checkLimit "$upLimit") ]] || { echo "upLimit is not formatted correctly: '$upLimit'"; return; }
	[[ -z $(checkLimit "$downLimit") ]] || { echo "downLimit is not formatted correctly: '$downLimit'"; return; }
	ip link show "$if" &> /dev/null || { echo "if is not a real interface: '$if'"; return; }
}

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
	tc -s qdisc show dev "$if"
	echo -e "\n== Interface: $ifb ==\n"
	tc -s qdisc show dev "$ifb"
	echo ""
}

# Delete queuing disciplines and restore NIC offloading.
function stop {
	# Delete queuing disciplines, if they exist.
	netRules=$(tc qdisc show dev "$if")
	[[ "$netRules" == *"qdisc htb 1: root"* ]] && tc qdisc delete dev "$if" root
	[[ "$netRules" == *"qdisc ingress ffff: parent ffff:fff1"* ]] && tc qdisc delete dev "$if" ingress

	ifbRules=$(tc qdisc show dev "$ifb")
	[[ "$ifbRules" == *"qdisc htb 1: root"* ]] && tc qdisc delete dev "$ifb" root

	# Offload network processing to NIC instead of CPU.
	etConfig=$(ethtool -k "$if")
	[[ "$etConfig" == *"tcp-segmentation-offload"* ]] && ethtool -K "$if" tso on
	[[ "$etConfig" == *"generic-segmentation-offload"* ]] && ethtool -K "$if" gso on
	[[ "$etConfig" == *"generic-receive-offload"* ]] && ethtool -K "$if" gro on

	# Turn off the ifb interface
	ip link set "$ifb" down
}

function start {
	# Delete existing queuing disciplines.
	stop

	# Make sure the traffic shaper is not bypassed.
	# These settings will offload network processing to the NIC when enabled.
	etConfig=$(ethtool -k "$if")
	[[ "$etConfig" == *"tcp-segmentation-offload"* ]] && ethtool -K "$if" tso off
	[[ "$etConfig" == *"generic-segmentation-offload"* ]] && ethtool -K "$if" gso off
	[[ "$etConfig" == *"generic-receive-offload"* ]] && ethtool -K "$if" gro off

	# Upload
	
	# Limit egress traffic using hbt and fq_codel.
	tc qdisc add dev "$if" root handle 1: htb default 1
	tc class add dev "$if" parent 1: classid 1:1 htb rate $upLimit
	tc qdisc add dev "$if" parent 1:1 fq_codel

	# Download

	# Turn on the ifb interface.
	ip link set "$ifb" up

	# Forward all incoming traffic to IFB where it will be rate limited.
	tc qdisc add dev "$if" handle ffff: ingress
	tc filter add dev "$if" parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev "$ifb"

	# Limit egress traffic for ifb using hbt and fq_codel.
	tc qdisc add dev "$ifb" root handle 1: htb default 1
	tc class add dev "$ifb" parent 1: classid 1:1 htb rate $downLimit
	tc qdisc add dev "$ifb" parent 1:1 fq_codel
}

problem=$(check)
if [[ -z "$problem" ]]; then
	case "$1" in
		"status") status ;;
		"stop") stop ;;
		"start") start ;;
		*) halp ;;
	esac
else echo "$problem"
fi
