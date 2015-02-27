#!/bin/bash
##############################################
# Do all prerun variables and safty measures #
# before anything else starts happening      #
##############################################
if [[ $(id -u) != 0 ]]; then # Verify we are root if not exit
   echo "Please Run This Script As Root or With Sudo!" 1>&2
   exit 1
fi

#retrieve absolute path structures so we can use symlinks and config files
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do # resolve $SOURCE until the file is no longer a symlink
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="${DIR}/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it's relativeness to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
DIR_CONF=/etc/n4p
DIR_LOGO=/usr/share/n4p

#######################################
# Building a sane working environment #
#######################################
get_name() # Retrieve the config values
{
    USE=$(grep $1 ${DIR_CONF}/n4p.conf | awk -F= '{print $2}')
}

get_state() # Retrieve the state of interfaces
{
    STATE=$(ip addr list | grep -i $1 | grep -i DOWN | awk -Fstate '{print $2}' | cut -d ' ' -f 2)
}

get_inet() # Retrieve the ip of the interface
{
    INET=$(ip addr list | grep -i $1 | grep -i inet | awk '{print $2}')
}

get_RCstatus() # What is the status from OpenRC of the service
{
    STATUS=$(/etc/init.d/net.$1 status | sed 's/* status: //g' | cut -d ' ' -f 2)
}

depends()
{
    get_name "NetworkManager="; NetworkManager=$USE
    get_name "IFACE0="; IFACE0=$USE
    get_name "IFACE1="; IFACE1=$USE
    get_name "ESSID="; ESSID=$USE
    get_name "STATION="; STATION=$USE
    get_name "LOCAL_BSSID="; LOCAL_BSSID=$USE
    get_name "CHAN="; CHAN=$USE
    get_name "BEACON="; BEACON=$USE
    get_name "PPS="; PPS=$USE
    get_name "AP="; UAP=$USE #This is what we name the AP via the config file
    get_name "BRIDGE_NAMED="; BRIDGE_NAMED=$USE
    get_name "BRIDGE_NAME_NAME="; BRIDGE_NAME_NAME=$USE
    get_name "ATTACK="; ATTACK=$USE
    get_name "VICTIM_BSSID="; VICTIM_BSSID=$USE
    get_name "TYPE="; TYPE=$USE
    get_name "ENCRYPTION="; ENCRYPTION=$USE
    get_name "MONITOR_MODE="; MONITOR_MODE=$USE
    get_name "OS="; OS=$USE
    IPT="/sbin/iptables"
    AP="at0" #This is the device name as per "ip addr"
    MON="${IFACE1}mon"
    VPN="tun0"
    VPNI="tap+"
    AP_GATEWAY=$(grep routers ${DIR_CONF}/dhcpd.conf | awk -Frouters '{print $2}' | cut -d ';' -f 1 | cut -d ' ' -f 2)
    AP_SUBNET=$(grep netmask ${DIR_CONF}/dhcpd.conf | awk -Fnetmask '{print $2}' | cut -d '{' -f 1 | cut -d ' ' -f 2 | cut -d ' ' -f 1)
    AP_IP=$(grep netmask ${DIR_CONF}/dhcpd.conf | awk -Fnetmask '{print $1}' | cut -d ' ' -f 1)
    AP_BROADCAST=$(grep broadcast-address ${DIR_CONF}/dhcpd.conf | awk -Fbroadcast-address '{print $2}' | cut -d ';' -f 1 | cut -d ' ' -f 2)
    # Text color variables
    TXT_UND=$(tput sgr 0 1)          # Underline
    TXT_BLD=$(tput bold)             # Bold
    BLD_RED=${txtbld}$(tput setaf 1) # red
    BLD_YEL=${txtbld}$(tput setaf 2) # Yellow
    BLD_ORA=${txtbld}$(tput setaf 3) # orange
    BLD_BLU=${txtbld}$(tput setaf 4) # blue
    BLD_PUR=${txtbld}$(tput setaf 5) # purple
    BLD_TEA=${txtbld}$(tput setaf 6) # teal
    BLD_WHT=${txtbld}$(tput setaf 7) # white
    TXT_RST=$(tput sgr0)             # Reset
    INFO=${BLD_WHT}*${TXT_RST}       # Feedback
    QUES=${BLD_BLU}?${TXT_RST}       # Questions
    PASS="${BLD_TEA}[${TXT_RSR}${BLD_WHT} OK ${TXT_RST}${BLD_TEA}]${TXT_RST}"
    WARN="${BLD_TEA}[${TXT_RST}${BLD_PUR} * ${TXT_RST}${BLD_TEA}]${TXT_RST}"
    # Start text with $BLD_YEL variable and end the text with $TXT_RST
}

settings()
{
    if [[ $NetworkManager == "True" ]]; then #n4p cant operate airmon and such with network manager hogging everything. We must kill it.
        if [[ $OS == "Pentoo" ]]; then
            get_RCstatus "$NetworkManager"
            [[ $STATUS != 'started' ]] && /etc/init.d/NetworkManager start
        else
            service network-manager stop
        fi
    else
        if [[ -e /etc/init.d/net.$IFACE1 ]]; then
            echo "$INFO Getting status of $IFACE1"
            get_RCstatus "$IFACE1"
            [[ $STATUS == 'started' ]] && /etc/init.d/net.$IFACE1 stop
        fi
    fi
}

rebuild_network()
{
    get_RCstatus $BRIDGE_NAME
    [[ $STATUS == 'started' ]] && /etc/init.d/net.$BRIDGE_NAME stop

    get_state "$BRDIGE"
    [[ $STATE != 'DOWN' ]] && ip link set $BRDIGE down

    brctl delif "$BRIDGE_NAME $RESP_BR_1"
    brctl delif "$BRIDGE_NAME $RESP_BR_2"
    brctl delbr "$BRIDGE_NAME"
    brctl show

    echo "$INFO It's now time to bring your default network interface back up"
    if [[ $NetworkManager != "True" ]]; then
        get_RCstatus "$IFACE0"
        if [[ $STATUS != 'started' ]]; then
            get_state "$IFACE0"
            [[ $STATE == 'DOWN' ]] && ip link set $IFACE0 up
            /etc/init.d/net.$IFACE0 start
        fi
        echo "$INFO The environment is now sanitized cya"
    else
        if [[ $OS == "Pentoo" ]]; then
            get_RCstatus "$NetworkManager"
            [[ $STATUS != 'started' ]] && /etc/init.d/NetworkManager start
        else
            service network-manager stop
        fi
    fi
    exit 0
}

#################################################################
#################Verify our DHCP and bridge needs################
#################################################################
openrc_bridge()
{
    # OpenRC needs sym links to bring the interface up. Verify they exist as needed if not make them then set proper state
    if [[ -e /etc/init.d/net.$BRIDGE_NAME ]]; then
        get_RCstatus "$BRIDGE_NAME"
        [[ $STATUS == 'started' ]] && /etc/init.d/net.$BRIDGE_NAME; sleep 1; ip link set $BRIDGE_NAME down
    else
        ln -s /etc/init.d/net.lo /etc/init.d/net.$BRIDGE_NAME
    fi

    if [[ -e /etc/init.d/net.$RESP_BR_1 ]]; then
        get_RCstatus "$RESP_BR_1"
        [[ $STATUS == 'started' ]] && /etc/init.d/net.$RESP_BR_1 stop; sleep 1; ip link set $RESP_BR_1 down
    fi

    if [[ -e /etc/init.d/net.$RESP_BR_2 ]]; then
        get_RCstatus "$RESP_BR_2"
        [[ $STATUS == 'started' ]] && /etc/init.d/net.$RESP_BR_2 stop; sleep 1; ip link set $RESP_BR_2 down
    fi

    # This insures $RESP_BR_1 & RESP_BR_2 does not have an ip and then removes it if it does since the bridge handles this
    get_inet "$RESP_BR_1"
    [[ -n $INET ]] && ip addr del $CHK_IP dev $RESP_BR_1

    get_inet "$RESP_BR_2"
    [[ -n $INET ]] && ip addr del $CHK_IP dev $RESP_BR_2

    echo -ne "\n Building $BRIDGE_NAME now with $BRIDGE_NAME $RESP_BR_2 $BRIDGE_NAME_RESP_BR_1"
    [[ $UAP == "HOSTAPD" ]] && iw dev $RESP_BR_2 set 4addr on

    get_state "$RESP_BR_2"
    while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $RESP_BR_2) ]]; do 
        sleep 0.2
        ip link set $RESP_BR_2 up
        get_state "$RESP_BR_2"
    done

    get_state "$RESP_BR_1"
    while [[ $STATE == 'DOWN' || -z $(ip addr list | grep $RESP_BR_1) ]]; do 
        sleep 0.2
        ip link set $RESP_BR_1 up
        get_state "$RESP_BR_1"
    done
    sleep 2
    brctl addbr $BRIDGE_NAME
    sleep 0.3
    brctl addif $BRIDGE_NAME $RESP_BR_1
    sleep 0.3
    brctl addif $BRIDGE_NAME $RESP_BR_2
    sleep 0.3
    ip link set $BRIDGE_NAME up
}

fbridge()
{
    if [[ $BRIDGE_NAMED == "True" ]]; then
        RESP_BR_1=$IFACE0
        [[ $AIRBASE == 'On' ]] && RESP_BR_2=$AP || RESP_BR_2=$IFACE1
        openrc_bridge
    elif [[ $BRIDGE_NAMED != "False" ]]; then
        echo "echo [$WARN] ERROR in n4p.conf configuration file, no Bridge found"
    fi
}




##################################################################
########################Start the menu############################
##################################################################
menu()
{   #This first if is mostly legacy and retained encase I do something with it in the future. I've yet to make use of it. Maybe you shouldh't expect me to
    if [[ $UAP == "AIRBASE" ]]; then
        MENUCHOICE=1
    elif [[ $UAP == "HOSTAPD" ]]; then
        MENUCHOICE=2
    else
        echo "${BLD_ORA}
        +==================+
        | 1) Airbase-NG    |
        | 2) Hostapd       |
        +==================+${TXT_RST}"
        read -e -p "Option: " MENUCHOICE
    fi

    if [[ $MENUCHOICE == 1 ]]; then
        get_name "ATTACK="; ATTACK=$USE
        if [[ $ATTACK == "Handshake" || $ATTACK == "Karma" || -z $ATTACK]]; then
            startairbase; keepalive
            [[ -z $ATTACK ]] && dhcp
        elif [[ $BRIDGE == "True" ]]; then
            fbridge; dhcp
        else
            echo "Bad attack method specified for this option."
        fi
    elif [[ MENUCHOICE == 2 ]]; then
        echo "Option Available tomarrow"
    else 
        clear; echo "$WARN Invalid option"; menu
    fi
}
depends
settings