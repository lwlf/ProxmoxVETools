#!/bin/bash

# 获取 PVE 存储列表
pve_storage=$(pvesm status | grep -E "nvme|ssd|hdd" | awk '{print $1}')
pve_storage_list=($(echo $pve_storage))

echo -e "$pve_storage" | awk 'BEGIN {print "序号\t存储名称"}{printf(NR"\t%s\n",$1)}'

# 输入磁盘列表
while :
do
    echo -n "请选择需要 PVE 存储序号：" && read pve_storage_number
    pve_storage_number=$(eval echo "$pve_storage_number")
    if [[ ! $pve_storage_number =~ ^[0-9]+$ ]] || [ $pve_storage_number -gt ${#pve_storage_list[@]} ] || [ "$pve_storage_number" -eq "0" ]; then
        echo "输入的 PVE 存储序号错误，请重新输入..."
        continue
    fi
    break
done

# 根据 PVE 存储获取磁盘
pve_storage_name=${pve_storage_list[$pve_storage_number-1]}
disk_name=$(lsblk -lno name,label | grep "${pve_storage_list[$pve_storage_number-1]}" | awk '{print $1}')
disk_full_name=/dev/$disk_name

# 移除 PVE 存储
pvesm remove $pve_storage_name 
umount $disk_full_name
sed -i "/$pve_storage_name/d" /etc/fstab
