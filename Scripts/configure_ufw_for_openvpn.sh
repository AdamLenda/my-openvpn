#!/bin/bash -e

umask 266;

#
# Constants
#
GENERAL_ERROR=1;
PARAM_ERROR=2;
INVALID_CIDR_ERROR=3;
SCRIPT_REQUIRES_ROOT=4;
UFW_CONFIGURATION_FAILED=5;
IP_FORWARDING_CONFIGURATION_FAILED=6;
UFW_REQUIRED=7;
IPCALC_REQUIRED=8;

#
# Utility Functions
#
function show {
    printf "${1}";
}

function showLn {
    printf "${1}\n";
}

function showCmd {
    printf "> ${1}\n";
    eval ${1}
}

function abort {
    printf "\nAborting!\n"
    echo $1 >&2
    code=${2}
    if ((code > 0)); then
        exit ${code};
    fi
    exit $GENERAL_ERROR;
}

function complete {
    printf "\nComplete: ${1}\n"
    exit 0
}

LastBegin="";
function begin {
    LastBegin=${1};
    printf "\nBegin ${LastBegin}\n";
}

function finish {
    printf "Finished ${LastBegin}\n";
    LastBegin="";
}

#
# Require Root
#

if [[ $EUID -ne 0 ]]; then
   abort "This script must be run as root" $SCRIPT_REQUIRES_ROOT
fi

#
# Dependencies
#
show "Verifying dependencies...";

command -v ufw >/dev/null 2>&1 || abort "\nThis script requires the ufw package be installed." $UFW_REQUIRED;

Version=`ufw --version | grep -E 'ufw ([0-9]+\.)+[0-9]+' | awk '{print $2}'`;

if [ ! "${Version}" = "0.35" ]; then
    showLn "\nWARNING: This script was built for ufw version 0.35\n";
fi

command -v ipcalc >/dev/null 2>&1 || abort "\nThis script requires the ipcalc package be installed." $IPCALC_REQUIRED;

showLn " Dependencies met.\n";

#
# Parameter Parsing
#
show "Verifying parameters...";

PARAMS=""

while (( "$#" )); do
  case "$1" in
    -b|--network-cidr-block)
      if [ -z "${2}" ]; then
        show "\nPlease provide network CIDR block for post-routing masquerade: "
        read NetworkCidrBlock
        shift 1
      else
        NetworkCidrBlock=$2
        shift 2
      fi
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      abort "Error: Unsupported flag $1" $PARAM_ERROR
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"

#
# Parameter Validation
#
showLn "Validating Parameters...";

# NetworkCidrBlock

if ipcalc -sc4 ${NetworkCidrBlock} >/dev/null; then
    showLn "Using IPv4"
elif ipcalc -sc6 ${NetworkCidrBlock} >/dev/null; then
    showLn "Using IPv6"
else
    abort "Parameter[network-cidr-block] \"${NetworkCidrBlock}\" is not recognized as an IPv4 or IPv6 CIDR Block." $INVALID_CIDR_ERROR
fi

if eval $(ipcalc -snp ${NetworkCidrBlock}); then
    showLn "Parameter[network-cidr-block] \"${NetworkCidrBlock}\" is a valid CIDR block."
    NetworkRangeIp=${NETWORK}
    NetworkRangePrefix=${PREFIX}
else
    abort "Parameter[network-cidr-block] \"${NetworkCidrBlock}\" is not a valid CIDR block." $INVALID_CIDR_ERROR
fi

#
# Configure ufw
#
showCmd "ufw --force reset";

begin "locking down ufw configuration files"
showCmd "chmod o-rwx /var/lib/ufw/user.rules;"
showCmd "chmod o-rwx /etc/ufw/after6.rules;"
showCmd "chmod o-rwx /var/lib/ufw/user6.rules;"
showCmd "chmod o-rwx /etc/ufw/before6.rules;"
showCmd "chmod o-rwx /etc/ufw/after.rules;"
showCmd "chmod o-rwx /etc/ufw/before.rules;"
finish

begin "modifying /etc/ufw/before.rules"

printf "
# OpenVpn Traffic from inside the network should masquerade as this host
*nat
:POSTROUTING ACCEPT [0.0]
-A POSTROUTING -s ${NETWORK}/${PREFIX} -o eth0 -j MASQUERADE
COMMIT
" > /tmp/before.rules;
cat /etc/ufw/before.rules >> /tmp/before.rules || abort "Failed to add default rules to new rules file" $UFW_CONFIGURATION_FAILED;
cat /tmp/before.rules > /etc/ufw/before.rules || abort "Failed to overwrite rules with new rules." $UFW_CONFIGURATION_FAILED;
rm -f /tmp/before.rules;
finish

begin "modifying /etc/default/ufw";
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw || abort "Failed to modify /etc/default/ufw" $UFW_CONFIGURATION_FAILED;
finish

begin "enable ip forwarding";
echo 1 > /proc/sys/net/ipv4/ip_forward || abort "Failed to modify /proc/sys/net/ipv4/ip_forward" $IP_FORWARDING_CONFIGURATION_FAILED;

printf "
#Enable packet forwarding for IPv4
net.ipv4.ip_forward=1
" > /etc/sysctl.d/75-openvpn-support.conf || abort "Failed to modify /etc/sysctl.d/75-openvpn-support.conf" $IP_FORWARDING_CONFIGURATION_FAILED;
finish

showCmd "ufw allow ssh";
showCmd "ufw allow 1194/udp";
showCmd "ufw --force enable;"
showCmd "ufw status" || abort "ufw status command failed";

showLn "ufw configuration for OpenVPN complete";