#!/bin/bash

# 获取磁盘列表（name,size,model,type,tran,rota:名称，大小，型号，类型，传输类型，是否可旋转）
disk_list_text=$(lsblk -drnx name -o name,size,model,type,tran,rota | grep "disk")
# 获取系统磁盘
system_disk_name=$(lsblk -no pkname $(findmnt -T / -o SOURCE | awk 'NR==2'))
# 获取所有已挂载分区
partition_list_mounted=$(lsblk -lo name,mountpoints | grep "/" | awk '!a[$0]++{print "/dev/"$1}')
# 获取已挂载的磁盘
disk_list_mounted=$(lsblk -x pkname -no pkname $partition_list_mounted | awk '!a[$0]++{print $1}')
# 过滤系统磁盘以及已挂载磁盘
disk_list_result_text=$(echo "$disk_list_text" | grep -v "$disk_list_mounted")
# 磁盘分组
OIFS=$IFS
IFS=$'\n'
disk_list=($disk_list_result_text)
IFS=$OIFS

# 格式化输出磁盘列表
disk_list_result_text_format=$(echo "$disk_list_result_text" | awk 'BEGIN {print "序号\t磁盘\t大小\t型号"}{printf(NR"\t%s\t%s\t%s\n",$1,$2,$3)}')

# 输出磁盘列表
echo -e "$disk_list_result_text_format"

# 输入磁盘列表
while :
do
    echo -n "请选择需要分区的磁盘序号：" && read disk_number
    disk_number=$(eval echo "$disk_number")
    if [[ ! $disk_number =~ ^[0-9]+$ ]] || [ $disk_number -gt ${#disk_list[@]} ] || [ "$disk_number" -eq "0" ]; then
        echo "输入的磁盘序号错误，请重新输入..."
        continue
    fi
    break
done

# 选择的磁盘
select_disk_arry=(${disk_list[$disk_number-1]})
select_disk_name=${select_disk_arry[0]}
select_disk_full_name=/dev/$select_disk_name

echo "你选择的磁盘：$select_disk_name"

# 选择的磁盘分区数
partition_number=$(fdisk -l $select_disk_full_name | grep "^$select_disk_full_name" | wc -l)

# 含有分区时需要确认
if [ $partition_number -gt 0 ]; then
    while :
    do
        echo -n "该磁盘已有分区，继续操作将会格式化该磁盘数据，是否继续（yes|No）？" && read is_continue
        case "${is_continue,,}" in
        "yes"|"y")
        # 删除所有分区
        sfdisk --delete $select_disk_full_name
        break
        ;;
        "no"|"n")
        exit 1
        ;;
        *)
        continue
        ;;
        esac
    done
fi

# 设置磁盘标签为 GPT，并创建分区
echo "label:gpt" | sfdisk $select_disk_full_name
echo ",,L" | sfdisk -a $select_disk_full_name
# 获取分区
select_disk_partition_name=$(sfdisk -l $select_disk_full_name | grep "^$select_disk_full_name" | awk '{print $1}')
echo "当前选择分区：$select_disk_partition_name"
# 格式化分区
mkfs.btrfs -f -m single -d single $select_disk_partition_name
# 获取分区 UUID
select_disk_partition_uuid=$(blkid -s UUID -o value ${select_disk_partition_name})
echo "当前选择分区 UUID：$select_disk_partition_uuid"

## 生成分区标签名
# 获取存储类型
storage_type="${select_disk_arry[4]}"
if [ "$storage_type" == "sata" ]; then
    if [  "${select_disk_arry[5]}" == "0" ]; then
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
select_disk_size=$(lsblk -dbno size $select_disk_full_name | numfmt --to=iec --format='%-1.0f')
storage_size=${select_disk_size,,}'b'
# 生成存储名称
storage_name="${storage_type}-${storage_number}-${storage_size}-btrfs"

# 设置分区标签名
btrfs filesystem label $select_disk_partition_name $storage_name
# 创建挂载目录：/mnt/pve
if [ ! -d /mnt/pve ]; then
    mkdir -p /mnt/pve
fi
partition_mount_path=/mnt/pve/$storage_name

# 创建 btrfs 子卷
btrfs subvolume create $partition_mount_path
# 挂载分区并设置开机挂载
mount $select_disk_partition_name $partition_mount_path
sed -i '$i\# New disk\n\UUID='"${select_disk_partition_uuid}"' '"${partition_mount_path}"' btrfs defaults,compress=lzo 0 1' /etc/fstab
# 获取 PVE 节点名称
pve_current_node=$(pvecm nodes | grep "local" | awk '{print $3}')
# 添加磁盘到 PVE 存储
pvesm add btrfs $storage_name --path $partition_mount_path --nodes $pve_current_node
