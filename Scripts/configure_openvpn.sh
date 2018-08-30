#!/bin/bash -e

umask 266;

#
# Constants
#
GENERAL_ERROR=1;
PARAM_ERROR=2;
INVALID_CIDR_ERROR=3;
SCRIPT_REQUIRES_ROOT=4;
OPENVPN_REQUIRED=7;
IPCALC_REQUIRED=8;

#
# Defaults
#
IncludeAwsDns=false;

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

command -v openvpn >/dev/null 2>&1 || abort "\nThis script requires the ufw package be installed." $OPENVPN_REQUIRED;

Version=`openvpn --version | grep -E 'OpenVPN ([0-9]+\.)+[0-9]+' | awk '{print $2}'`;

if [ ! "${Version}" = "2.4.6" ]; then
    showLn "\nWARNING: This script was built for OpenVPN version 2.4.6";
fi

command -v ipcalc >/dev/null 2>&1 || abort "\nThis script requires the ipcalc package be installed." $IPCALC_REQUIRED

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
        show "\nPlease provide network CIDR block for VPN traffic forwarding: "
        read NetworkCidrBlock
        shift 1
      else
        NetworkCidrBlock=$2
        shift 2
      fi
      ;;
    -v|--vpn-client-ip-cidr-block)
      if [ -z "${2}" ]; then
        show "\nPlease provide vpn client CIDR block: "
        read VpnClientCidrBlock
        shift 1
      else
        VpnClientCidrBlock=$2
        shift 2
      fi
      ;;
    --include-aws-dns)
      IncludeAwsDns=true;
      shift 1
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

if eval $(ipcalc -snpm ${NetworkCidrBlock}); then
    showLn "Parameter[network-cidr-block] \"${NetworkCidrBlock}\" is a valid CIDR block."
    NetworkRangeIp=${NETWORK}
    NetworkRangePrefix=${PREFIX}
    NetworkNetmask=${NETMASK}
else
    abort "Parameter[network-cidr-block] \"${NetworkCidrBlock}\" is not a valid CIDR block." $INVALID_CIDR_ERROR
fi

# VpnClientCidrBlock

if ipcalc -sc4 ${VpnClientCidrBlock} >/dev/null; then
    showLn "Using IPv4"
elif ipcalc -sc6 ${VpnClientCidrBlock} >/dev/null; then
    showLn "Using IPv6"
else
    abort "Parameter[vpn-client-ip-cidr-block] \"${VpnClientCidrBlock}\" is not recognized as an IPv4 or IPv6 CIDR Block." $INVALID_CIDR_ERROR
fi

if eval $(ipcalc -snpm ${VpnClientCidrBlock}); then
    showLn "Parameter[vpn-client-ip-cidr-block] \"${VpnClientCidrBlock}\" is a valid CIDR block."
    VpnClientIpRangeIp=${NETWORK}
    VpnClientIpRangePrefix=${PREFIX}
    VpnClientIpRangeNetmask=${NETMASK}
else
    abort "Parameter[vpn-client-ip-cidr-block] \"${VpnClientCidrBlock}\" is not a valid CIDR block." $INVALID_CIDR_ERROR
fi

#
# Find Name Servers
#

DhcpOptions=""
if [ "${GenerateServerFiles}" = true ]; then

    begin "including aws name servers... "
    NameServerIps=( $(grep -P '^nameserver\s+[^$]+$' /etc/resolv.conf | awk '{print $2}') )
    NameServerCount=0
    for ip in "${NameServerIps[@]}"
    do
       :
        let NameServerCount=NameServerCount+1
        if ((NameServerCount > 1)); then
            DhcpOptions="${DhcpOptions}\n"
        fi
        DhcpOptions="${DhcpOptions}push \"dhcp-option DNS ${ip}\""
    done
    showLn "Found ${NameServerCount} Name Server IPs";
    finish
fi

# add public DHCP servers as well
showLn "Including public DNS servers"
DhcpOptions="${DhcpOptions}
push \"dhcp-option DNS 1.1.1.1\"
push \"dhcp-option DNS 9.9.9.9\"";

#
# Show Summary
#

showLn "
Configuring OpenVPN to allow access to:
${NetworkRangeIp}/${NetworkRangePrefix} and Netmask: ${NetworkNetmask}

Connected Clients will be issued an IP from:
${VpnClientIpRangeIp}/${VpnClientIpRangePrefix} and Netmask: ${VpnClientIpRangeNetmask}

Found ${NameServerCount} Name Servers:
${NameServerIps[@]}

Using DHCP Options:
${DhcpOptions}";

#
# Configure OpenVpn
#

begin "configuring OpenVpn... "

OpenVpnConfig="port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key  # This file should be kept secret
dh dh2048.pem
server ${VpnClientIpRangeIp} ${VpnClientIpRangeNetmask}
ifconfig-pool-persist ipp.txt
keepalive 10 120
cipher AES-256-CBC
user nobody
group nobody
persist-key
persist-tun
status openvpn-status.log
verb 3
explicit-exit-notify 1
push \"redirect-gateway def1 bypass-dhcp\"
;push \"route ${NetworkRangeIp} ${NetworkNetmask} vpn_gateway\"
${DhcpOptions}
";

show "\nUsing OpenVPN Server Config:\n${OpenVpnConfig}\n"

printf "${OpenVpnConfig}" > /etc/openvpn/server/server.conf

finish
