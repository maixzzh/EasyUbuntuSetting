#!/usr/bin/env bash
# ============================================================================
#  和风悬浮小药丸 · Waybar 主题 — Ubuntu 安装脚本
#  Wafuu Floating Pills — Waybar theme installer for Ubuntu
# ----------------------------------------------------------------------------
#  用法:
#     ./install.sh                 正常安装
#     ./install.sh --dry-run       只打印将要执行的操作, 不实际改动系统
#     ./install.sh --yes           不交互确认 (适合 CI / 一键脚本)
#     ./install.sh --skip-deps     跳过 apt 安装 (依赖已就绪时)
#     ./install.sh --skip-fonts    跳过字体安装
#     ./install.sh --uninstall     卸载, 还原备份
#
#  设计原则:
#    1. 全程幂等 —— 重复执行不会产生副作用, 可安全重跑
#    2. 先备份后覆盖 —— 任何已存在的配置都会带时间戳备份, 随时可回滚
#    3. 不做越权的事 —— 除了 apt 和字体, 不碰任何系统目录;
#       用户的 Hyprland 配置只打印提示, 绝不擅自修改
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
#  常量与路径
# ---------------------------------------------------------------------------
# 脚本所在目录 (即仓库根目录)。用 BASH_SOURCE 而非 $0, 保证被 source 时也对
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/config"

# Waybar 读取配置的固定位置, 由 XDG 规范决定, 不可更改
DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"

# 字体装到用户级目录 —— 这样不需要 sudo, 也不会污染系统字体
FONT_DIR="$HOME/.local/share/fonts"

# Nerd Font 版本。想锁定版本把 latest 换成 v3.3.0 这类 tag 即可
NERD_FONT_VERSION="${NERD_FONT_VERSION:-latest}"

STAMP="$(date +%Y%m%d-%H%M%S)"

# Ubuntu 官方源里就能装到的依赖。每项都标注了用途, 删减时请留意
APT_PACKAGES=(
    waybar                  # 本体。Ubuntu 24.10+ / 25.x 在 universe 源
    pavucontrol             # 点音量图标 → 图形化音量控制
    network-manager-gnome   # 提供 nm-connection-editor, 点网络图标 → 图形化网络设置
    gnome-system-monitor    # 点 CPU/内存/磁盘图标 → 图形化系统监视器
    wlogout                 # 点电源图标 → 图形化电源菜单
    wl-clipboard            # 提供 wl-copy, 右键时钟复制时间
    fonts-noto-cjk          # 工作区汉字 一~十 的字形来源
    curl                    # 下载 Nerd Font
    unzip                   # 解压 Nerd Font
)

# 以下包非必需, 缺失只影响单个功能, 不会导致安装失败
APT_OPTIONAL=(
    gnome-calendar          # 点时钟 → 日历。不需要可自行安装
)

# ---------------------------------------------------------------------------
#  命令行参数
# ---------------------------------------------------------------------------
DRY_RUN=0; ASSUME_YES=0; SKIP_DEPS=0; SKIP_FONTS=0; DO_UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN=1 ;;
        --yes|-y)     ASSUME_YES=1 ;;
        --skip-deps)  SKIP_DEPS=1 ;;
        --skip-fonts) SKIP_FONTS=1 ;;
        --uninstall)  DO_UNINSTALL=1 ;;
        -h|--help)    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数: $arg (用 --help 查看用法)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
#  输出辅助 —— 颜色只在终端里启用, 重定向到文件时自动关闭, 避免污染日志
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_INFO=$'\033[36m'
else
    C_RESET=''; C_BOLD=''; C_OK=''; C_WARN=''; C_ERR=''; C_INFO=''
fi

STEP=0
step()    { STEP=$((STEP + 1)); printf '\n%s━━━ 步骤 %d/%d · %s ━━━%s\n' \
              "$C_BOLD$C_INFO" "$STEP" "$TOTAL_STEPS" "$1" "$C_RESET"; }
info()    { printf '  %s▸%s %s\n' "$C_INFO" "$C_RESET" "$1"; }
ok()      { printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$1"; }
warn()    { printf '  %s⚠%s %s\n' "$C_WARN" "$C_RESET" "$1"; }
err()     { printf '  %s✗%s %s\n' "$C_ERR" "$C_RESET" "$1" >&2; }
# 说明块: 用缩进的灰色文字解释"这一步为什么要做"
why()     { printf '    %s%s%s\n' "$C_INFO" "$1" "$C_RESET"; }

# 统一封装命令执行。dry-run 下只回显不执行, 这是能用 --dry-run 预览的关键
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '    %s[dry-run]%s %s\n' "$C_WARN" "$C_RESET" "$*"
    else
        "$@"
    fi
}

confirm() {
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY_RUN" = 1 ]   && return 0
    printf '  %s?%s %s [y/N] ' "$C_WARN" "$C_RESET" "$1"
    read -r reply </dev/tty || return 1
    case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

TOTAL_STEPS=6
[ "$DO_UNINSTALL" = 1 ] && TOTAL_STEPS=3

# ===========================================================================
#  卸载流程
# ===========================================================================
if [ "$DO_UNINSTALL" = 1 ]; then
    printf '%s╔══════════════════════════════════════════════════╗%s\n' "$C_BOLD" "$C_RESET"
    printf '%s║   和风悬浮小药丸 · 卸载                          ║%s\n' "$C_BOLD" "$C_RESET"
    printf '%s╚══════════════════════════════════════════════════╝%s\n' "$C_BOLD" "$C_RESET"

    step "检查当前安装"
    if [ ! -d "$DEST_DIR" ]; then
        warn "未发现 $DEST_DIR, 没什么可卸载的"
        exit 0
    fi
    ok "找到 $DEST_DIR"

    step "移走主题文件"
    why "只删本主题部署的文件, 保留备份和你自己加的东西"
    for f in config.jsonc style.css; do
        if [ -f "$DEST_DIR/$f" ]; then
            run mv "$DEST_DIR/$f" "$DEST_DIR/$f.removed-$STAMP"
            ok "$f → $f.removed-$STAMP"
        fi
    done
    [ -d "$DEST_DIR/scripts" ] && run rm -rf "$DEST_DIR/scripts" && ok "scripts/ 已移除"

    step "还原备份"
    why "如果安装时备份过旧配置, 这里问你要不要还原回去"
    LATEST_BAK="$(find "$DEST_DIR" -maxdepth 1 -name 'config.jsonc.bak-*' 2>/dev/null | sort | tail -1 || true)"
    if [ -n "$LATEST_BAK" ]; then
        info "发现备份: $LATEST_BAK"
        if confirm "还原这个备份?"; then
            run cp "$LATEST_BAK" "$DEST_DIR/config.jsonc"
            ok "已还原 config.jsonc"
        fi
    else
        info "没有找到备份文件"
    fi

    printf '\n  卸载完成。重启 waybar 生效: pkill waybar; waybar &\n\n'
    exit 0
fi

# ===========================================================================
#  正式安装流程
# ===========================================================================
printf '%s╔══════════════════════════════════════════════════╗%s\n' "$C_BOLD" "$C_RESET"
printf '%s║   和风悬浮小药丸 · Waybar 主题安装               ║%s\n' "$C_BOLD" "$C_RESET"
printf '%s║   Wafuu Floating Pills for Ubuntu                ║%s\n' "$C_BOLD" "$C_RESET"
printf '%s╚══════════════════════════════════════════════════╝%s\n' "$C_BOLD" "$C_RESET"
[ "$DRY_RUN" = 1 ] && warn "DRY-RUN 模式: 只预览, 不会真的改动系统"

# ---------------------------------------------------------------------------
step "环境检查"
# ---------------------------------------------------------------------------
why "先确认系统版本和前提条件。本主题依赖 Hyprland 和较新的 waybar,"
why "在错误的发行版上安装会得到一堆难以排查的怪问题, 所以这里提前拦下。"

# 1) 必须是 Ubuntu / Debian 系, 否则 apt 那一套不成立
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    info "发行版: ${PRETTY_NAME:-未知}"
    case "${ID:-}${ID_LIKE:-}" in
        *ubuntu*|*debian*) ok "属于 Debian 系, apt 可用" ;;
        *) warn "不是 Ubuntu/Debian 系。本脚本的 apt 安装步骤会失败, 请手动装依赖" ;;
    esac
    # 2) 版本检查: waybar 在 Ubuntu 24.10 才进入 universe 源
    if [ "${ID:-}" = "ubuntu" ] && [ -n "${VERSION_ID:-}" ]; then
        if [ "${VERSION_ID%%.*}" -lt 24 ] || { [ "${VERSION_ID%%.*}" -eq 24 ] && [ "${VERSION_ID##*.}" -lt 10 ]; }; then
            warn "检测到 Ubuntu $VERSION_ID。官方源的 waybar 太旧 (24.04 只有 0.9.24),"
            warn "本主题需要 waybar >= 0.11。建议升级到 24.10 或更新, 或改用 PPA"
        else
            ok "Ubuntu $VERSION_ID, 官方源含 waybar"
        fi
    fi
else
    warn "读不到 /etc/os-release, 跳过发行版检查"
fi

# 3) Hyprland 检查。本主题的 workspaces / submap 模块靠 Hyprland 的 IPC 取数据,
#    没有 Hyprland 这两个模块会静默消失 —— 不报错, 只是不显示, 极难排查
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    ok "检测到正在运行的 Hyprland 会话"
elif command -v Hyprland >/dev/null 2>&1; then
    warn "装了 Hyprland 但当前不在 Hyprland 会话里 (HYPRLAND_INSTANCE_SIGNATURE 为空)"
    warn "workspaces / submap 模块只在 Hyprland 会话内才会显示"
else
    warn "未检测到 Hyprland。本主题可在任意 Wayland 合成器上运行,"
    warn "但 hyprland/workspaces 和 hyprland/submap 两个模块不会显示"
fi

# 4) 已有 waybar 版本
if command -v waybar >/dev/null 2>&1; then
    WB_VER="$(waybar --version 2>/dev/null | awk '{print $NF}')"
    info "已安装 waybar: $WB_VER"
    # 版本号比较: 取主次版本, 0.11 以下的部分占位符不支持
    if [ "$(printf '%s\n' "0.11" "$WB_VER" | sort -V | head -1)" != "0.11" ]; then
        warn "waybar $WB_VER 偏旧, 部分占位符 (如 {avg_frequency}) 可能不支持,"
        warn "表现为单个模块整体消失并在日志里报 'argument not found'"
    fi
else
    info "未安装 waybar, 将在下一步安装"
fi

# 5) 确认配置源文件都在
for f in config.jsonc style.css scripts/diskio.sh; do
    if [ ! -f "$SRC_DIR/$f" ]; then
        err "缺少源文件: $SRC_DIR/$f"
        err "请确认在仓库根目录执行, 且文件完整 (git clone 是否完整?)"
        exit 1
    fi
done
ok "配置文件齐全"

# ---------------------------------------------------------------------------
step "安装系统依赖 (apt)"
# ---------------------------------------------------------------------------
why "本主题用到 4 个图形化工具响应点击:"
why "  · pavucontrol          → 点音量图标"
why "  · nm-connection-editor → 点网络图标"
why "  · gnome-system-monitor → 点 CPU / 内存 / 磁盘图标"
why "  · wlogout              → 点电源图标"
why "它们全部来自 Ubuntu 官方源, 不需要任何 PPA 或第三方源。"

if [ "$SKIP_DEPS" = 1 ]; then
    warn "已按 --skip-deps 跳过"
else
    # 先确认哪些真的缺, 只装缺的, 避免无谓地动系统
    MISSING=()
    for pkg in "${APT_PACKAGES[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            info "已安装: $pkg"
        else
            MISSING+=("$pkg")
        fi
    done

    if [ ${#MISSING[@]} -eq 0 ]; then
        ok "所有依赖都已就绪, 无需安装"
    else
        info "需要安装: ${MISSING[*]}"
        # 任何 apt 操作前必须 update, 否则可能因为索引过期找不到包
        why "先 apt update 刷新索引, 否则可能因为索引过期而找不到包"
        if confirm "使用 sudo 执行 apt update && apt install?"; then
            run sudo apt-get update
            # --no-install-recommends 不加以, 否则 gnome 系工具会拖进大量
            # 非必要组件; 依赖关系 apt 会自动解析, 不影响功能
            run sudo apt-get install -y --no-install-recommends "${MISSING[@]}"
            ok "依赖安装完成"
        else
            warn "已跳过。相关图标点击后将没有反应"
        fi
    fi

    # 可选包单独处理, 装不上也不算失败
    for pkg in "${APT_OPTIONAL[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            info "可选包未安装: $pkg (仅影响点时钟打开日历)"
        fi
    done
fi

# ---------------------------------------------------------------------------
step "安装字体"
# ---------------------------------------------------------------------------
why "本主题的图标全部来自 Nerd Font。Nerd Font 没有进入 Ubuntu 官方源,"
why "必须从上游下载。安装在 ~/.local/share/fonts (用户级), 不需要 sudo,"
why "也不影响系统字体目录。"
why ""
why "另外需要 fonts-noto-cjk 提供工作区汉字 一~十 的字形 —— 那个在上一步"
why "已经随 apt 装好了。若那一步被跳过, 汉字会显示成方块。"

if [ "$SKIP_FONTS" = 1 ]; then
    warn "已按 --skip-fonts 跳过"
else
    # 判断 Nerd Font 是否就位。用 fc-match 实际解析一次, 比查文件更可靠
    if fc-match "Hack Nerd Font" 2>/dev/null | grep -q "Hack Nerd Font"; then
        ok "Hack Nerd Font 已安装"
    else
        info "未检测到 Hack Nerd Font, 开始下载..."
        mkdir -p "$FONT_DIR"
        TMP_ZIP="$(mktemp -d)/Hack.zip"
        # 注入 trap: 无论脚本正常结束还是被 Ctrl-C, 都清掉临时文件
        trap 'rm -rf "$(dirname "$TMP_ZIP")"' EXIT

        why "从 Nerd Font 官方 GitHub Release 下载 Hack 字体包 (~4MB)"
        # latest 会跳到最新 release; 想锁定版本用 NERD_FONT_VERSION=v3.3.0
        FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/${NERD_FONT_VERSION}/download/Hack.zip"
        info "来源: $FONT_URL"

        if run curl -fsSL --retry 3 -o "$TMP_ZIP" "$FONT_URL"; then
            # -o 覆盖而不是合并, 避免重复安装时堆一堆同名文件
            run unzip -o -q "$TMP_ZIP" -d "$FONT_DIR"
            # 必须刷新字体缓存, 否则新装的字体对已运行的程序不可见
            why "刷新字体缓存 (fc-cache)。不做这一步, waybar 会找不到新字体"
            run fc-cache -f "$FONT_DIR"
            ok "字体安装完成"
        else
            err "字体下载失败。请检查网络, 或手动下载后解压到 $FONT_DIR"
            err "手动地址: https://github.com/ryanoasis/nerd-fonts/releases"
            warn "跳过字体安装, 图标将显示为方块"
        fi
    fi
fi

# ---------------------------------------------------------------------------
step "备份现有配置"
# ---------------------------------------------------------------------------
why "覆盖前先备份。Waybar 只认 ~/.config/waybar 这一个位置, 没有"
why "多配置文件机制, 所以只能原地覆盖 —— 备份是唯一的后悔药。"
why "备份带时间戳, 多次安装不会互相覆盖, 也方便用 --uninstall 还原。"

if [ ! -d "$DEST_DIR" ]; then
    info "$DEST_DIR 不存在, 无需备份 (属于全新安装)"
else
    BACKED=0
    for f in config.jsonc config style.css; do
        if [ -f "$DEST_DIR/$f" ]; then
            run cp "$DEST_DIR/$f" "$DEST_DIR/$f.bak-$STAMP"
            ok "已备份 $f → $f.bak-$STAMP"
            BACKED=1
        fi
    done
    [ "$BACKED" = 0 ] && info "目录存在但没有配置文件, 跳过"
    [ -d "$DEST_DIR/scripts" ] && info "注意: 已存在的 scripts/ 目录会被覆盖"
fi

# ---------------------------------------------------------------------------
step "部署配置"
# ---------------------------------------------------------------------------
why "把仓库里的文件放到 waybar 的固定查找路径:"
why "  config/config.jsonc   → ~/.config/waybar/config.jsonc"
why "  config/style.css      → ~/.config/waybar/style.css"
why "  config/scripts/*.sh   → ~/.config/waybar/scripts/  (需可执行权限)"
why ""
why "配置文件里的图标全部写成 \\uXXXX 转义而非直接粘贴字形, 这样文件"
why "是纯 ASCII, 经过 git / 压缩 / 复制都不会损坏。这是有意的设计,"
why "改配置时请保持这种做法 (原因见 README 的「常见问题」)。"

run mkdir -p "$DEST_DIR/scripts"
run install -m 0644 "$SRC_DIR/config.jsonc" "$DEST_DIR/config.jsonc"
ok "config.jsonc 已部署"
run install -m 0644 "$SRC_DIR/style.css"   "$DEST_DIR/style.css"
ok "style.css 已部署"
# -m 0755 保证脚本可执行 —— 少了执行位 waybar 会静默不显示该模块
run install -m 0755 "$SRC_DIR/scripts/diskio.sh" "$DEST_DIR/scripts/diskio.sh"
ok "scripts/diskio.sh 已部署 (含执行权限)"

# ---------------------------------------------------------------------------
step "校验"
# ---------------------------------------------------------------------------
why "装完立刻自检, 把问题在安装阶段就暴露出来, 而不是让你对着一个"
why "空白的状态栏猜原因。"

FAIL=0

# 1) JSONC 语法。注意 config.jsonc 含 // 注释, 标准 JSON 解析器会拒绝,
#    这里先剥掉注释再解析, 逻辑与 waybar 内部的 JsonCpp 行为一致
if command -v python3 >/dev/null 2>&1; then
    if python3 - "$DEST_DIR/config.jsonc" <<'PY'
import json, sys
src = open(sys.argv[1], encoding='utf-8').read()
out, i, n, instr, esc = [], 0, len(src), False, False
while i < n:
    c = src[i]
    if instr:
        out.append(c)
        if esc: esc = False
        elif c == '\\': esc = True
        elif c == '"': instr = False
        i += 1
    else:
        if c == '"': instr = True; out.append(c); i += 1
        elif src.startswith('//', i):
            while i < n and src[i] != '\n': i += 1
        else: out.append(c); i += 1
json.loads(''.join(out))
PY
    then ok "config.jsonc 语法正确"
    else err "config.jsonc 语法错误, waybar 会退回默认配置"; FAIL=1
    fi
else
    warn "无 python3, 跳过语法校验"
fi

# 2) 磁盘脚本能否产出合法 JSON。这是唯一的外部脚本, 值得单独验一次
if [ -x "$DEST_DIR/scripts/diskio.sh" ]; then
    OUT="$("$DEST_DIR/scripts/diskio.sh" 2>/dev/null || true)"
    # 第一次运行只建立基线, 全部为 0 属正常; 再跑一次才会算出速率
    sleep 1
    OUT="$("$DEST_DIR/scripts/diskio.sh" 2>/dev/null || true)"
    if printf '%s' "$OUT" | grep -q '"text"'; then
        ok "diskio.sh 输出正常: $OUT"
    else
        err "diskio.sh 未输出预期 JSON, 磁盘模块会显示为空"
        warn "手动排查: bash $DEST_DIR/scripts/diskio.sh"
        FAIL=1
    fi
else
    err "diskio.sh 不可执行 (缺少执行权限)"; FAIL=1
fi

# 3) 字体是否真的能被解析到
if fc-match "Hack Nerd Font" 2>/dev/null | grep -q "Hack Nerd Font"; then
    ok "字体 Hack Nerd Font 可解析"
else
    err "找不到 Hack Nerd Font, 图标会显示成方块 ▯"
    warn "手动排查: fc-list | grep -i nerd"
    FAIL=1
fi
if fc-match "Noto Sans CJK JP" 2>/dev/null | grep -qi "CJK"; then
    ok "字体 Noto Sans CJK 可解析 (汉字工作区名正常)"
else
    warn "找不到 Noto Sans CJK, 工作区的 一~十 会显示成方块"
    warn "修复: sudo apt install fonts-noto-cjk"
fi

# 4) 点击动作依赖的命令是否都在。缺了不会报错, 只是点了没反应 ——
#    这正是最难自查的一类问题, 所以这里逐个点名
info "检查点击动作依赖的命令:"
for c in pavucontrol nm-connection-editor gnome-system-monitor wlogout wl-copy nmcli wpctl gnome-calendar; do
    if command -v "$c" >/dev/null 2>&1; then
        ok "$c"
    else
        warn "$c 不存在 —— 对应图标点击后不会有任何反应"
    fi
done

# 5) 如果 waybar 正跑着, 让它重载配置
if pgrep -x waybar >/dev/null 2>&1; then
    why "SIGUSR2 是 waybar 约定的「重载配置」信号 (见 man 5 waybar)"
    if run pkill -SIGUSR2 waybar; then
        ok "已通知正在运行的 waybar 重载配置"
    fi
else
    info "waybar 当前未运行, 稍后按下面的方法启动"
fi

# ---------------------------------------------------------------------------
step "Hyprland 侧配置 (需你手动完成)"
# ---------------------------------------------------------------------------
why "以下两项不在 waybar 范围内, 脚本不会擅自改你的合成器配置。"
why "它们只影响体验, 不影响状态栏本身能否显示。"

cat <<EOF

  ${C_BOLD}1. 自启动 waybar${C_RESET}
     在 Hyprland 配置里加一行 (文件通常是 ~/.config/hypr/hyprland.conf):
         exec-once = waybar

  ${C_BOLD}2. 启动 polkit 认证代理 —— 强烈建议${C_RESET}
     图形化的网络设置 (nm-connection-editor) 在保存配置时需要弹授权框。
     polkit 代理负责弹这个框; 没有它, 操作会「静默失败」—— 点保存没反应,
     也不报错, 是新手最难排查的一类问题。

     Ubuntu 上可选的代理 (任选其一, 装完记得加到 exec-once):
         sudo apt install lxpolkit        # 最轻量, 推荐
         sudo apt install mate-polkit
         sudo apt install policykit-1-gnome

     加完后的 exec-once 形如:
         exec-once = lxpolkit
         exec-once = waybar

  ${C_BOLD}3. 让面板浮窗化 (可选)${C_RESET}
     若你把点击目标改成了 KDE 面板 (plasmawindowed), 需要窗口规则让它
     居中浮出而不是平铺。本项目提供现成片段:
         hyprland/windowrule.conf   — 标准 hyprland.conf 写法
         hyprland/windowrule.lua    — Lua 配置写法

EOF

printf '%s' "$C_BOLD"
if [ "$FAIL" = 0 ]; then
    printf '  安装完成, 全部校验通过 ✓\n'
else
    printf '  安装完成, 但有项目未通过校验, 请查看上面的 ✗ 项\n'
fi
printf '%s\n' "$C_RESET"
echo "  启动 / 重启 waybar:"
echo "      pkill waybar; waybar &"
echo
echo "  查看运行日志 (排查模块不显示的首选手段):"
echo "      waybar -l debug"
echo
echo "  卸载并还原备份:"
echo "      ./install.sh --uninstall"
echo

[ "$FAIL" = 0 ] || exit 1
