#!/usr/bin/env bash

#### this script uses the following environment variables

# CLUSTER_CIDR: the cidr of the current cluster
# TUNNEL_SERVICE_CIDRs: comma-separated services CIDRs of the remote clusters 
# SERVICE_CIDR_KUBECONFIGs: comma-separated pairs of serivce cidr and file containing the kubeconfig for that cidr. each pair is separated by '-'
# POD_IP
# POD_NAME
# LOG_LEVEL: 0 to 10

set -o nounset
set -o errexit

function setupServiceProxy {
  echo $SERVICE_CIDR_KUBECONFIGs
  port=20244
  for pair in ${SERVICE_CIDR_KUBECONFIGs//,/ }
  do
    echo 'preparing kuberouter for' kubeconfig: ${pair#*-} and cidr: ${pair%-*} 
    kube-router --run-service-proxy=true --run-firewall=false --run-router=false --kubeconfig=${pair#*-} --standalone=true --standalone-iface=eth0 --standalone-hostname=$POD_NAME --standalone-ip=$POD_IP --v $LOG_LEVEL --service-cidr=${pair%-*}  --health-port=$port &
    port=$(($port+1))
  done  
}

function wireOVSInOutServices {
  echo running wireOVSInOutServices
  # retrieve the vethdevice name
  iflink=$(cat /sys/class/net/eth0/iflink)
  veth=$(nsenter -t 1 -n ip link | grep "$iflink: veth" | awk '{print $2}' | cut -d '@' -f 1)
  port=$(ovs-vsctl get Interface $veth ofport)
  mac=$(cat /sys/class/net/eth0/address)
  for cidr in ${TUNNEL_SERVICE_CIDRs//,/ }
  do
    echo cluster_cidr: $CLUSTER_CIDR , cidr: $cidr , port: $port , mac: $mac
  # table=0, priority=300,ip,nw_src=10.128.0.0/14, nw_dst=10.132.0.0/14 actions=output:<port_of_tunnel>
  # to modify the destination address: mod_dl_dst:mac
    ovs-ofctl add-flow br0 "table=0,priority=300,ip,nw_src=$CLUSTER_CIDR,nw_dst=$cidr,actions=mod_dl_dst:$mac,output:$port" --protocols=OpenFlow13
  #From remote tunnel to local network 
  # table=0, priority=300,ip,nw_src=10.132.0.0/14, nw_dst=10.128.0.0/14 action=goto_table:30
    ovs-ofctl add-flow br0 "table=0,priority=300,ip,in_port=$port,nw_src=$cidr,nw_dst=$CLUSTER_CIDR,action=goto_table:30" --protocols=OpenFlow13
  done  
}

function unWreOVSInOutServices {
  echo running unWreOVSInOutServices
  # retrieve the vethdevice name
  set +e
  iflink=$(cat /sys/class/net/eth0/iflink)
  veth=$(nsenter -t 1 -n ip link | grep "$iflink: veth" | awk '{print $2}' | cut -d '@' -f 1)
  port=$(ovs-vsctl get Interface $veth ofport)
  mac=$(cat /sys/class/net/eth0/address)
  for cidr in ${TUNNEL_SERVICE_CIDRs//,/ }
  do
    echo cluster_cidr: $CLUSTER_CIDR , cidr: $cidr , port: $port
  # table=0, priority=300,ip,nw_src=10.128.0.0/14, nw_dst=10.132.0.0/14 actions=output:<port_of_tunnel>
    ovs-ofctl del-flows br0 "table=0,priority=300,ip,nw_src=$CLUSTER_CIDR,nw_dst=$cidr,actions=mod_dl_dst:$mac,output:$port" --protocols=OpenFlow13
  #From remote tunnel to local network 
  # table=0, priority=300,ip,nw_src=10.132.0.0/14, nw_dst=10.128.0.0/14 action=goto_table:30
    ovs-ofctl del-flows br0 "table=0,priority=300,ip,in_port=$port,nw_src=$cidr,nw_dst=$CLUSTER_CIDR,action=goto_table:30" --protocols=OpenFlow13
  done
  set -e  
  }

function cleanupAndExit {
  cleanup
  exit 0
  }

function setup {
  setupServiceProxy
  wireOVSInOutServices
  }

function cleanup {
  unWreOVSInOutServices
  }


cleanup  
trap cleanupAndExit TERM
setup
sleep infinity & wait $!
trap - TERM