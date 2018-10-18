#!/usr/bin/env bash

#### this script uses the following environment variables
# TUNNEL_PORT : the port used to establish the tunnel
# TUNNEL_DEV_NAME : the device used to establush the tunnel
# TUNNEL_REMOTE_PEER : the peer IP or VIP to which establish the tunnel 
# TUNNEL_LOCAL_PEER : the local IP to be used for the tunnel
# TUNNEL_CIDR : the CIDR that should be routed thoru this tunnel in x.x.x.x/x format
# TUNNEL_PRIVATE_KEY: the private key
# TUNNEL_PEER_PUBLIC_KEY: the peer's public key
# TUNNEL_MODE: implementnation of the tunnel (fou, socat, socatcs, wireguard)
# WIREGUARD_CONFIG: location of the wireguard config file
# CLUSTER_CIDR: the cidr of the current cluster
# TUNNEL_CIDRs: comma separated CIDRs of the remote clusters
# KUBE_CONFIG: directory of the kubeconfig files
# TUNNEL_SERVICE_CIDRs: comma separated services CIDRs of the remote clusters  
# ROUTE_SERVICE: boolean to set whether service routing should be setup


set -o nounset
set -o errexit

function setupServiceProxy {
  for file in $KUBE_CONFIG/*
  do
    kube-router --run-service-proxy=true --run-firewall=false --run-router=false --kubeconfig=$file --standalone=true --standalone-iface=eth0 --standalone-hostname=$POD_NAME --standalone-ip=$POD_IP &
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

function setupFouTunnel {
  echo running setupFouTunnel
  ip fou add port $TUNNEL_PORT ipproto 4
  ip link add name $TUNNEL_DEV_NAME type ipip remote $TUNNEL_REMOTE_PEER local $TUNNEL_LOCAL_PEER ttl 225 encap fou encap-sport \
    auto encap-dport $TUNNEL_PORT
  ip addr add $TUNNEL_CIDR dev $TUNNEL_DEV_NAME
  }


# wg completely in the pod's network namespace

function setupWg {
  echo running setupwg
  #sysctl -w net.ipv4.ip_forward=1
  ip link add dev $TUNNEL_DEV_NAME type wireguard
  #ip link set $TUNNEL_DEV_NAME netns $$
  wg setconf $TUNNEL_DEV_NAME $WIREGUARD_CONFIG
  ip link set up dev $TUNNEL_DEV_NAME
  for cidr in ${TUNNEL_CIDRs//,/ }
  do
    ip route add $cidr dev $TUNNEL_DEV_NAME
  done    
}

function setup {
  echo running setup
  
  if [ $TUNNEL_MODE = "fou" ] 
  then
    setupFouTunnel
    wireOVSPodInOut   
  elif [ $TUNNEL_MODE = "wireguard" ] 
  then
    setupWg
    wireOVSPodInOut            
  fi
  if [ $ROUTE_SERVICES = "True" ]
  then  
    setupServiceProxy
    wireOVSInOutServices
  fi       
  }

function cleanup {
  echo running cleanup

  if [ $TUNNEL_MODE = "fou" ] 
  then
    unwireOVSPodInOut
  elif [ $TUNNEL_MODE = "wireguard" ] 
  then
    unwireOVSPodInOut       
  fi
  if [ $ROUTE_SERVICES = "True" ]
  then  
    unWreOVSInOutServices
  fi  
  }

function wireOVSPodInOut {
  echo running wireOVSPodInOut
  # retrieve the vethdevice name
  iflink=$(cat /sys/class/net/eth0/iflink)
  veth=$(nsenter -t 1 -n ip link | grep "$iflink: veth" | awk '{print $2}' | cut -d '@' -f 1)
  port=$(ovs-vsctl get Interface $veth ofport)
  mac=$(cat /sys/class/net/eth0/address)
  for cidr in ${TUNNEL_CIDRs//,/ }
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

function unwireOVSPodInOut {
  echo running unwireOVSPodInOut
  # retrieve the vethdevice name
  set +e
  iflink=$(cat /sys/class/net/eth0/iflink)
  veth=$(nsenter -t 1 -n ip link | grep "$iflink: veth" | awk '{print $2}' | cut -d '@' -f 1)
  port=$(ovs-vsctl get Interface $veth ofport)
  mac=$(cat /sys/class/net/eth0/address)
  for cidr in ${TUNNEL_CIDRs//,/ }
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


cleanup  
trap cleanupAndExit TERM
setup
sleep infinity & wait $!
trap - TERM

