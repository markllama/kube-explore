#!/bin/sh

ssh-keygen

cat <<EOF >>/etc/hosts
10.19.138.41 smc-master.cloud.lab.eng.bos.redhat.com master
10.19.138.42 smc-work1.cloud.lab.eng.bos.redhat.com work1
10.19.138.43 smc-work2.cloud.lab.eng.bos.redhat.com work2
EOF

sed -i -e '/^UserKnown/s/^/#/' /root/.ssh/config

ssh-copy-id localhost
ssh-copy-id work1
ssh-copy-id work2

export ALL_HOSTS="localhost work1 work2"
export WORKER_HOSTS="work1 work2"



for HOST in $ALL_HOSTS ; do
    echo disable swap and firewalld on $HOST
    ssh $HOST swapoff -a
    ssh $HOST sed -i -e "'/swap/s/^/#/'" /etc/fstab
    #ssh $HOST systemctl stop firewalld
    #ssh $HOST systemctl disable firewalld
    #ssh $HOST systemctl mask firewalld
    echo
done

export MASTER_PORTS="6443/tcp 2379-2380/tcp 10250-10252/tcp"
export WORKER_PORTS="10250/tcp 30000-32767/tcp"
export WEAVE_PORTS="6783/tcp 6783-6784/udp"

for PORT in $MASTER_PORTS ; do
    echo adding port: $PORT
    firewall-cmd --zone public --add-port $PORT
    firewall-cmd --zone public --add-port $PORT --permanent
    echo
done

for PORT in $WORKER_PORTS ; do
    for HOST in $WORKER_HOSTS ; do
        echo adding port $PORT on $HOST
        ssh $HOST firewall-cmd --zone public --add-port $PORT
        ssh $HOST firewall-cmd --zone public --add-port $PORT --permanent
    done
done



for HOST in $ALL_HOSTS ; do
    echo enable epel repo on $HOST
    yum -y install epel-release
    echo
done

for HOST in $ALL_HOSTS ; do
    echo installing host virtualization systems on $HOST
    ssh $HOST yum -y install docker libvirt qemu-kvm
    ssh $HOST systemctl enable docker
    ssh $HOST systemctl start docker
    ssh $HOST systemctl enable libvirtd
    ssh $HOST systemctl start libvirtd
    echo
done

# cat <<EOF > ip_vs.conf
# ip_vs
# ip_vs_rr
# ip_vs_wrr
# ip_vs_sh
# EOF

# for HOST in $ALL_HOSTS ; do
#     yum install -y ipvsadm
#     scp ip_vs.conf $HOST:/etc/modules-load.d/ip_vs.conf
#     ssh $HOST systemctl restart systemd-modules-load
#     lsmod | grep ip_
# done

cat <<EOF >  k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
for HOST in $ALL_HOSTS ; do
    scp k8s.conf $HOST:/etc/sysctl.d/k8s.conf
    ssh $HOST sysctl --system
done


cat <<EOF > kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF

cp kubernetes.repo /etc/yum.repos.d
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable kubelet
systemctl start kubelet

kubeadm init
export KUBECONFIG=/etc/kubernetes/admin.conf

#
# Add ports for Weave network
#
for PORT in $WEAVE_PORTS ; do
    for HOST in $ALL_HOSTS ; do
         echo adding port $PORT on $HOST
         ssh $HOST firewall-cmd --zone public --add-port $PORT
         ssh $HOST firewall-cmd --zone public --add-port $PORT --permanent
     done
done


# install weave network
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"


for HOST in $WORKER_HOSTS ; do
    scp kubernetes.repo $HOST:/etc/yum.repos.d
    ssh $HOST setenforce 0
    ssh $HOST sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    ssh $HOST yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    ssh $HOST systemctl enable kubelet
    ssh $HOST systemctl start kubelet
done



 kubeadm join 10.19.138.41:6443 --token <value> --discovery-token-ca-cert-hash sha256:<hash>


 export VERSION=v0.10.0
