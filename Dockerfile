FROM fedora

USER root
    
RUN INSTALL_PKGS="openvswitch git iproute wireguard-tools psmisc tcpdump nmap-ncat wget ipvsadm iptables bind-utils" && \
    dnf install -y 'dnf-command(copr)' && \
    dnf copr enable -y jdoss/wireguard && \
    dnf install -y ${INSTALL_PKGS} && \
    dnf clean all && \
    rm -rf /var/cache/yum         

ADD tunnel.sh /tunnel.sh

ENTRYPOINT ["/tunnel.sh"]    