#!/bin/bash

# 获取系统磁盘
system_disk=$(lsblk -no pkname $(findmnt -T / -o SOURCE | awk 'NR==2'))
# 获取未挂载分区
partitions=$(lsblk -lo label,name,size,type,mountpoints | grep "part" | grep -Ev "/|$system_disk")

# 磁盘分组
OIFS=$IFS
IFS=$'\n'
partition_list=($partitions)
IFS=$OIFS

echo "$partitions" | awk 'BEGIN{print "序号\t分区\t大小\t标签"}{printf(NR"\t%s\t%s\t%s\n",$2,$3,$1)}'

while :
do
    echo -n "请选择需要的分区序号：" && read part_number
    part_number=$(eval echo "$part_number")
    if [[ ! $part_number =~ ^[0-9]+$ ]] || [ $part_number -gt ${#partition_list[@]} ] || [ "$part_number" -eq "0" ]; then
        echo "输入的分区错误，请重新输入..."
        continue
    fi
    break
done

partition_name=$(echo "${partition_list[part_number-1]}" | awk '{print $2}')
partition_full_name=/dev/$partition_name
partition_label_name=$(echo "${partition_list[part_number-1]}" | awk '{print $1}')
partition_uuid=$(blkid -s UUID -o value ${partition_full_name})
partition_mount_path=/mnt/pve/$partition_label_name

if [ ! -d $partition_mount_path ]; then
    mkdir -p /mnt/pve
    btrfs subvolume create $partition_mount_path
fi

# 添加 PVE 存储
mount $partition_full_name $partition_mount_path
sed -i '$i\# New disk: '"${partition_label_name}"'\nUUID='"${partition_uuid}"' '"${partition_mount_path}"' btrfs defaults,compress=lzo 0 1' /etc/fstab
#pve_current_node=$(pvecm nodes | grep "local" | awk '{print $3}')
pve_current_node=$(hostname)
pvesm add btrfs $partition_label_name --path $partition_mount_path --nodes $pve_current_node
