FROM centos

ENV GOPATH=/opt/app-root/go \
    GOBIN=/opt/app-root/go/bin \
    PATH=$PATH:/opt/app-root/go/bin 

USER root
    
RUN INSTALL_PKGS="golang git iproute wireguard-tools psmisc tcpdump nmap-ncat wget openssl-devel openssl python-six python-sphinx gcc make python-devel openssl-devel kernel-devel graphviz kernel-debug-devel autoconf automake rpm-build redhat-rpm-config libtool python-twisted-core python-zope-interface PyQt4 desktop-file-utils libcap-ng-devel groff checkpolicy selinux-policy-devel ipvsadm" && \
    curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo && \
    curl -Lo ./epel-release-latest-7.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm && \ 
    yum install -y ./epel-release-latest-7.noarch.rpm && \
    yum install -y ${INSTALL_PKGS} && \
    mkdir -p ~/rpmbuild/SOURCES && \
    wget http://openvswitch.org/releases/openvswitch-2.9.2.tar.gz && \
    cp openvswitch-2.9.2.tar.gz ~/rpmbuild/SOURCES/ && \
    tar xfz openvswitch-2.9.2.tar.gz && \
    rpmbuild -bb --nocheck openvswitch-2.9.2/rhel/openvswitch-fedora.spec && \
    yum localinstall ~/rpmbuild/RPMS/x86_64/openvswitch-2.9.2-1.el7.x86_64.rpm -y && \  
    yum clean all && \
    rm -rf ~/rpmbuild && \
    rm openvswitch-2.9.2.tar.gz && \
    mkdir -p ${GOPATH}/{bin,src} && \
    curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh && \
    cd $GOPATH/src && \
    mkdir -p github.com/cloudnativelabs && \
    cd github.com/cloudnativelabs && \
    git clone https://github.com/cloudnativelabs/kube-router && \
    cd kube-router && \
    git checkout v0.2.0 && \
    dep ensure -vendor-only && \
    go build -o kube-router cmd/kube-router/kube-router.go && \
    cp ./kube-router /usr/bin/kube-router && \
    cd /root && \
    rm -rf ${GOPATH}    
    

ADD tunnel.sh /tunnel.sh

ENTRYPOINT ["/tunnel.sh"]    