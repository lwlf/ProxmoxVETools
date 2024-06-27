#!/bin/bash

test ! "$(pvesm status | grep 'local-btrfs')" && {
echo "PVE 存储 local-btrfs 不存在"
exit 1
}

# 获取根目录磁盘分区
system_partition=$(findmnt -T / -o SOURCE | awk 'NR==2')
system_disk="/dev/$(lsblk -no pkname $system_partition)"
system_partition_properties=($(lsblk -ldno name,tran,rota $system_disk))

## 生成 PVE 存储名称
# 获取存储类型
storage_type="${system_partition_properties[1]}"
if [ "$storage_type" == "sata" ]; then
    if [  "${system_partition_properties[2]}" == "0" ]; then
        storage_type="ssd"
    else
        storage_type="hdd"
    fi
else
    storage_type="$storage_type"
fi
# 获取 PVE 存储列表
pvestorage_list=$(pvesm status | grep -v "Name.*Type" | awk '{print $1}')
# 过滤 PVE 存储列表
storage_list=$(echo "$pvestorage_list" | grep "$storage_type")
# 获取 PVE 存储序号（输出匹配符）
number_pattern_str=$(echo "$storage_list"  | awk -F'-' -v ORS='|' '{print $2}' | sed 's/.$//g')
# 生成存储序号
storage_number=$(seq -f "%02g" 1 99 | grep -Ev "$number_pattern_str" | sort | awk 'NR==1')
# 处理为空时的序号
test ! "$storage_number" && storage_number="00"
# 获取存储大小
select_disk_size=$(lsblk -dbno size $system_partition | numfmt --to=iec --format='%-1.0f')
storage_size=${select_disk_size,,}'b'
# 生成存储名称
storage_name="${storage_type}-${storage_number}-${storage_size}-btrfs"
partition_mount_path=/mnt/pve/$storage_name
# 设置系统分区标签名
#btrfs filesystem label $system_partition $storage_name

if [ ! -d $partition_mount_path ]; then
    mkdir -p /mnt/pve
    btrfs subvolume create $partition_mount_path
fi

# 移除 local-btrfs 存储
pvesm remove local-btrfs
# 添加存储
#pve_current_node=$(pvecm nodes | grep "local" | awk '{print $3}')
pve_current_node=$(hostname)
pvesm add btrfs $storage_name --path $partition_mount_path --nodes $pve_current_node
# 移动原数据至新目录
mv /var/lib/pve/local-btrfs/* $partition_mount_path
