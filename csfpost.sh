#!/bin/bash
#################################################################################################################
# Script to prepare and restore full docker iptables rules.                                                     #
#                                                                                                               #
# (C)2018 Owen Grok Yon                                                                                         #
# This script is provided as-is; no liability can be accepted for use.                                          #
# You are free to modify and reproduce so long as this attribution is preserved.                                #
#                                                                                                               #
#                                                                                                               #
# Make sure to disable Docker's iptables management with --iptables=false.                                      #
# CSF needs to be restarted whenever you make structural changes to Docker \                                    #
# such as your networks, bridges or IP configuration.  Or restart csf after rescreate conpose                   #
#                                                                                                               #
#################################################################################################################
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
#################################################################################################################
# Add ports for accessing only with csf.allow (for monitoring or other sec rules)
ign_ports=("9100" "9121" "9122" "9113" "9253")

# Basic firewall rules
iptables -N DOCKER
iptables -t nat -N DOCKER
iptables -t nat -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
iptables -t nat -A OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER

# Setup bridges
setup_bridge() {
    local bridge=$(docker network inspect $1 -f '{{(index .Options "com.docker.network.bridge.name")}}')
    local network=$(docker network inspect $1 -f '{{(index .IPAM.Config 0).Subnet}}')

    if [[ -z "$bridge" ]]; then
        bridge="br-${1}"
    fi

    echo -n "Setup bridge.. "
    iptables -t nat -A POSTROUTING -s $network ! -o $bridge -j MASQUERADE
    iptables -t nat -A DOCKER -i $bridge -j RETURN
    iptables -A FORWARD -o $bridge -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -o $bridge -j DOCKER
    iptables -A FORWARD -i $bridge ! -o $bridge -j ACCEPT
    iptables -A FORWARD -i $bridge -o $bridge -j ACCEPT
    echo "$bridge DONE"
}

# Setup rules for open ports
setup_conport() {
    # for every network
    for network in $(docker inspect $1 -f '{{range $bridge, $conf := .NetworkSettings.Networks}}{{$bridge}}{{end}}'); do

        ipaddress=$(docker inspect $1 -f "{{(index .NetworkSettings.Networks \"${network}\").IPAddress}}")
        bridge=$(docker network inspect $network -f '{{(index .Options "com.docker.network.bridge.name")}}')

        if [[ -z "$bridge" ]]; then
            bridge="br-$(docker network inspect ${network} -f '{{.Id}}' | cut -c -12)"
        fi
        rules=$(docker port $1 | sed 's/ //g')
        if [ `echo ${rules} | wc -c` -gt "1" ]; then
            for rule in ${rules}; do
                src=`echo ${rule} | awk -F'->' '{ print $2 }'`
                dst=`echo ${rule} | awk -F'->' '{ print $1 }'`
                src_ip=`echo ${src} | awk -F':' '{ print $1 }'`
                src_port=`echo ${src} | awk -F':' '{ print $2 }'`
                dst_port=`echo ${dst} | awk -F'/' '{ print $1 }'`
                dst_proto=`echo ${dst} | awk -F'/' '{ print $2 }'`
                echo -n "Setup port rules.. "
                # Add localinput check
                iptables -A DOCKER -d ${ipaddress}/32 ! -i $bridge -o $bridge -p ${dst_proto} -m conntrack --ctstate NEW -m ${dst_proto} --dport ${dst_port} -j LOCALINPUT
                # check if port is ignored
                ck_rq=0
                for chk_port in ${ign_ports[*]}; do
                    if [ ${dst_port} = ${chk_port} ]; then
                        ck_rq=1
                    fi
                done
                # Add access freom anywhere
                if [ ${ck_rq} -eq 0 ]; then
                    iptables -A DOCKER -d ${ipaddress}/32 ! -i $bridge -o $bridge -p ${dst_proto} -m ${dst_proto} --dport ${dst_port} -j ACCEPT
                fi
                # Add masquare for port (! need or no????)
                iptables -t nat -A POSTROUTING -s ${ipaddress}/32 -d ${ipaddress}/32 -p ${dst_proto} -m ${dst_proto} --dport ${dst_port} -j MASQUERADE
                # Add nat for port (need for ip)
                iptables_opt_src=""
                if [ ${src_ip} != "0.0.0.0" ]; then
                    iptables_opt_src="-d ${src_ip}/32 "
                fi
                iptables -t nat -A DOCKER ${iptables_opt_src}! -i $bridge -p ${dst_proto} -m ${dst_proto} --dport ${src_port} -j DNAT --to-destination ${ipaddress}:${dst_port}
                echo "${dst_port} DONE"
            done
        fi
    done
}

# Loop through networks and setup bridge traffics
for network in $(docker network ls | grep -Ev 'host|none|NETWORK' | awk '{print $1}' | sort); do
    setup_bridge $network
done

# Loop through containers and setup basic port forwarding
for container in $(docker ps -q); do
    setup_conport $container
done

# end file