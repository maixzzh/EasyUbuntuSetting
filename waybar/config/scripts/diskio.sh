#!/usr/bin/env bash
# ============================================================================
#  Waybar 磁盘读写速率模块 (custom/diskio)
# ----------------------------------------------------------------------------
#  数据源: /proc/diskstats —— 纯内核接口, 不需要安装任何东西
#  输出:   Waybar JSON (text / tooltip / class)
#
#  为什么要自己写: Waybar 内置的 disk 模块显示的是「磁盘剩余空间」,
#  不是读写速度, 两者不是一回事。测 I/O 速率必须自己采样两次求差。
#
#  坑: 本机根分区是 btrfs 子卷, findmnt 返回 /dev/nvme0n1p7[/@]
#      末尾的 [/@] 必须剥掉, 否则设备名解析成 "@]" 什么都读不到
# ============================================================================
set -u

STATE="${XDG_RUNTIME_DIR:-/tmp}/waybar-diskio.state"

# ---------------------------------------------------------------- 设备探测
detect_disk() {
    local src
    src=$(findmnt -no SOURCE / 2>/dev/null) || return 0
    src="${src%%[*}"     # /dev/nvme0n1p7[/@]  ->  /dev/nvme0n1p7
    src="${src##*/}"     # /dev/nvme0n1p7      ->  nvme0n1p7
    case "$src" in
        nvme*|mmcblk*) echo "${src%p[0-9]*}" ;;   # nvme0n1p7 -> nvme0n1
        sd*|vd*|hd*)   echo "${src%[0-9]*}"  ;;   # sda2      -> sda
        *)             echo "" ;;
    esac
}

DISK="${WAYBAR_DISK:-$(detect_disk)}"

# ---------------------------------------------------------------- 读取计数
# /proc/diskstats 字段: 3=设备名  6=已读扇区  10=已写扇区  (1 扇区 = 512B)
read_stats() {
    if [ -n "$DISK" ]; then
        awk -v d="$DISK" '$3==d {print $6, $10; f=1} END{if(!f) print "0 0"}' /proc/diskstats
    else
        # 探测失败时汇总所有物理盘 (排除 zram/loop/分区)
        lsblk -dno NAME,TYPE 2>/dev/null \
            | awk '$2=="disk" && $1 !~ /^(zram|loop)/ {print $1}' > "$STATE.disks"
        awk -v f="$STATE.disks" '
            BEGIN { while ((getline n < f) > 0) want[n] = 1 }
            $3 in want { r += $6; w += $10 }
            END { print r+0, w+0 }
        ' /proc/diskstats
        rm -f "$STATE.disks"
    fi
}

now=$(date +%s%N)
read -r rsec wsec <<< "$(read_stats)"

# ------------------------------------------------- 与上次采样求差 (算速率)
if [ -r "$STATE" ]; then
    read -r pt pr pw < "$STATE" 2>/dev/null || { pt=$now; pr=$rsec; pw=$wsec; }
else
    pt=$now; pr=$rsec; pw=$wsec
fi
printf '%s %s %s\n' "$now" "$rsec" "$wsec" > "$STATE"

dt_ms=$(( (now - pt) / 1000000 ))
[ "$dt_ms" -lt 100 ] && dt_ms=100          # 防止首次运行除零/爆表

dr=$(( (rsec - pr) * 512 )); [ "$dr" -lt 0 ] && dr=0   # 计数器回绕保护
dw=$(( (wsec - pw) * 512 )); [ "$dw" -lt 0 ] && dw=0

rrate=$(( dr * 1000 / dt_ms ))             # 字节/秒
wrate=$(( dw * 1000 / dt_ms ))

# ---------------------------------------------------------------- 人类可读
human() {
    local b=$1
    if   [ "$b" -ge 1073741824 ]; then
        printf '%d.%dG' $(( b / 1073741824 )) $(( b % 1073741824 * 10 / 1073741824 ))
    elif [ "$b" -ge 1048576 ]; then
        printf '%d.%dM' $(( b / 1048576 )) $(( b % 1048576 * 10 / 1048576 ))
    elif [ "$b" -ge 1024 ]; then
        printf '%dK' $(( b / 1024 ))
    else
        printf '%dB' "$b"
    fi
}

# ------------------------------------------------------------------- 输出
#  读 = 从磁盘读进来, 写 = 写回磁盘
ICON_DISK=$'\uf0a0'
ICON_READ=$'\uf019'
ICON_WRITE=$'\uf093'
text="${ICON_DISK}${ICON_READ} $(human "$rrate") ${ICON_WRITE} $(human "$wrate")"

total=$(( rrate + wrate ))
class="normal"
if   [ "$total" -ge 52428800 ]; then class="critical"   # >= 50 MB/s
elif [ "$total" -ge 10485760 ]; then class="warning"    # >= 10 MB/s
fi

tooltip="磁盘读写 (${DISK:-汇总})\\n读取  $(human "$rrate")/s\\n写入  $(human "$wrate")/s"
[ "$class" = "critical" ] && tooltip="$tooltip\\n(高负载)"
[ "$class" = "warning" ]  && tooltip="$tooltip\\n(负载偏高)"

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
