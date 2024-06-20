#!/bin/bash

# 取消 PVE 订阅源
sed -i 's|^deb|# deb|g' /etc/apt/sources.list.d/pve-enterprise.list

# 添加 PVE 非订阅源
source /etc/os-release && echo "deb https://mirrors.ustc.edu.cn/proxmox/debian/pve ${VERSION_CODENAME} pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list

# 更换 CEPH 仓库源
CEPH_LIST=/etc/apt/sources.list.d/ceph.list
test -f $CEPH_LIST && cp $CEPH_LIST ${CEPH_LIST}.bak
CEPH_CODENAME=`ceph -v | grep ceph | awk '{print $(NF-1)}'`
source /etc/os-release
echo "deb https://mirrors.ustc.edu.cn/proxmox/debian/ceph-$CEPH_CODENAME $VERSION_CODENAME no-subscription" > $CEPH_LIST

# 更换 CT 模板源
sed -i.bak 's|http://download.proxmox.com|https://mirrors.ustc.edu.cn/proxmox|g' /usr/share/perl5/PVE/APLInfo.pm
systemctl restart pvedaemon

# 更换 Debian 软件源
sed -i.bak 's|^deb http://ftp.debian.org|deb https://mirrors.ustc.edu.cn|g' /etc/apt/sources.list
sed -i 's|^deb http://security.debian.org|deb https://mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list

# 更新索引
apt update
