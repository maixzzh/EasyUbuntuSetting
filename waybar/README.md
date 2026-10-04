# 和风悬浮小药丸 · Wafuu Floating Pills

> 为 Hyprland 打造的日系和风 Waybar 状态栏主题。
> 抹茶绿 × 樱花粉，每个模块独立成"悬浮药丸"，磨砂白底 + 樱花描边 + 柔和投影。

<!-- 建议替换成你自己的截图。注意: 状态栏是透明的, 截图会带上壁纸,
     请确认壁纸版权后再公开。 -->
<!-- ![preview](preview.png) -->

---

## 特性

- **悬浮药丸**：摒弃整条长背景，每个模块独立成丸，之间留白
- **和风配色**：抹茶绿 `#A2D1A7` / 樱花粉 `#FFB7C5`，取自日系插画
- **汉字工作区**：工作区用 一 二 三 四 五 而非阿拉伯数字
- **真实磁盘 I/O 速率**：Waybar 内置 `disk` 模块只有"剩余空间"，
  本项目自带脚本读 `/proc/diskstats` 算出真实读写速度
- **负载分级变色**：CPU / 内存 / 磁盘 / 电量超阈值自动变色告警
- **丝滑过渡**：全局 `transition` 缓动，悬停与状态切换不生硬

## 环境要求

| 项目 | 要求 | 说明 |
|---|---|---|
| 发行版 | **Ubuntu 24.10 / 25.x 及以上** | 24.04 官方源的 waybar 是 0.9.24，太旧 |
| 合成器 | **Hyprland** | 其他 Wayland 合成器可用，但工作区模块不显示 |
| Waybar | **>= 0.11** | 见下方「常见问题」的版本差异说明 |
| 字体 | Hack Nerd Font + Noto Sans CJK | 安装脚本会自动处理 |

## 快速开始

```bash
git clone <你的仓库地址> ~/EasyUbuntu
cd ~/EasyUbuntu/waybar
./install.sh
```

先预览会做什么、不实际改动系统：

```bash
./install.sh --dry-run
```

其他参数：

```bash
./install.sh --yes           # 不交互确认
./install.sh --skip-deps     # 跳过 apt（依赖已就绪）
./install.sh --skip-fonts    # 跳过字体下载
./install.sh --uninstall     # 卸载并还原备份
```

---

## 安装脚本做了什么

脚本分 6 步，每步都会打印它**为什么**要这么做。

### 步骤 1 · 环境检查

确认发行版是 Debian 系、Ubuntu 版本 >= 24.10、waybar 版本 >= 0.11，
并检查 Hyprland 会话是否存在。

> **为什么要在装之前拦一道**：这个主题依赖较新的 waybar 和 Hyprland 的 IPC。
> 在错误的环境上安装不会报错，只会得到一堆"模块凭空消失"的怪现象，
> 事后排查成本远高于装之前检查一次。

### 步骤 2 · 安装系统依赖

只装缺失的包，全部来自 **Ubuntu 官方源**，不需要任何 PPA：

| 包 | 用途 |
|---|---|
| `waybar` | 状态栏本体 |
| `pavucontrol` | 点音量图标 → 图形化音量控制 |
| `network-manager-gnome` | 提供 `nm-connection-editor`，点网络图标 → 图形化网络设置 |
| `gnome-system-monitor` | 点 CPU / 内存 / 磁盘图标 → 图形化系统监视器 |
| `wlogout` | 点电源图标 → 图形化电源菜单 |
| `wl-clipboard` | 提供 `wl-copy`，右键时钟复制时间 |
| `fonts-noto-cjk` | 工作区汉字 一~十 的字形 |

> **为什么点击不用 KDE 面板**：KDE 的 `plasmawindowed` 面板体验更好，
> 但要为一个状态栏装进大半个 Plasma，对 Ubuntu 用户不划算。
> 想要 KDE 面板的话，见 `hyprland/` 目录下的说明自行替换 `on-click` 即可。

### 步骤 3 · 安装字体

Nerd Font 没有进入 Ubuntu 官方源，脚本从上游 GitHub Release 下载
Hack Nerd Font，安装到 `~/.local/share/fonts`（用户级，**不需要 sudo**，
也不污染系统字体目录），然后刷新字体缓存。

> **为什么必须刷新缓存**：`fc-cache` 不做的话，已经运行的程序看不到新字体，
> waybar 会报"找不到字体"并把所有图标渲染成方块 ▯。

### 步骤 4 · 备份现有配置

Waybar 只认 `~/.config/waybar` 一个位置，没有多配置机制，只能原地覆盖。
脚本会把你已有的 `config.jsonc` / `style.css` 带**时间戳**备份，
多次安装不会互相覆盖。

### 步骤 5 · 部署配置

拷贝 `config/` 下的文件到 `~/.config/waybar/`，
并给 `diskio.sh` 加上执行权限（`0755`）。

> **执行权限不是可有可无的**：少了它，waybar 不会报错，
> 磁盘模块会静默地什么都不显示。

### 步骤 6 · 校验

安装后立即自检，把问题在安装阶段就暴露：

- 用与 waybar 内部 `JsonCpp` 一致的逻辑剥离注释后校验 JSON 语法
- 实际运行一次 `diskio.sh`，确认能输出合法 JSON
- 用 `fc-match` 确认两个字体都能被解析到
- **逐个检查所有 `on-click` 依赖的命令是否存在**（缺了不会报错，只是点了没反应）
- 若 waybar 正在运行，发送 `SIGUSR2` 让它重载配置

---

## 自定义

### 改配色

`config/style.css` 顶部注释标了全部色值，全局替换即可。常用位置：

```css
/* 药丸底 · 描边 · 投影 */
background-color: rgba(255, 255, 255, 0.75);
border: 1px solid rgba(214, 122, 145, 0.85);
box-shadow: 0px 2px 5px rgba(220, 180, 190, 0.3);

/* 悬停：樱花粉 + 白字 */
background-color: rgba(255, 192, 203, 0.8);

/* 活动工作区：抹茶绿 */
background-color: #A2D1A7;

/* 告警色 */
#FFB347  /* warning 琥珀 */
#FF69B4  /* critical 品红 */
```

> ⚠ **GTK3 不支持 CSS 变量**。`var(--x)` 和 `:root {}` 是 GTK4 的写法，
> 在 Waybar 里会让**整段样式静默失效**。网上很多配置抄的是 GTK4 版本，
> 照抄会踩这个坑。颜色必须写字面量。

### 改模块排布

编辑 `config/config.jsonc` 里的 `modules-left` / `modules-center` / `modules-right`：

```jsonc
"modules-left":   ["hyprland/workspaces", "hyprland/submap",
                   "cpu", "memory", "custom/diskio"],
"modules-center": ["clock"],
"modules-right":  ["network", "pulseaudio", "battery", "tray", "custom/power"],
```

### 改告警阈值

```jsonc
"cpu":    { "states": { "warning": 60, "critical": 85 } },
"memory": { "states": { "warning": 70, "critical": 90 } },
"battery":{ "states": { "warning": 30, "critical": 15 } },
```

磁盘 I/O 的阈值在 `config/scripts/diskio.sh` 末尾：

```bash
if   [ "$total" -ge 52428800 ]; then class="critical"   # >= 50 MB/s
elif [ "$total" -ge 10485760 ]; then class="warning"    # >= 10 MB/s
```

### 监控指定的磁盘

`diskio.sh` 默认自动探测根分区所在的物理磁盘。想手动指定：

```jsonc
"custom/diskio": {
    "exec": "WAYBAR_DISK=nvme1n1 $HOME/.config/waybar/scripts/diskio.sh",
    ...
}
```

### 换成 KDE 面板

把 `on-click` 改成：

```jsonc
"network":    { "on-click": "plasmawindowed org.kde.plasma.networkmanagement" },
"pulseaudio": { "on-click": "plasmawindowed org.kde.plasma.volume" },
```

需额外安装 `plasma-workspace`、`plasma-nm`、`plasma-pa`，
并参考 `hyprland/` 下的窗口规则片段让它浮窗化。

---

## 常见问题排查

### 图标显示成方块 ▯ / 图标完全不显示

**这是本项目最容易踩的坑，分两种情况：**

**情况 A：文件里的图标字符被吃掉了**

Nerd Font 的图标位于 Unicode 私有使用区（PUA，`U+E000`–`U+F8FF`）。
不少编辑器、剪贴板、代码托管平台会在传输中**静默丢弃**这些字符——
不报错，文件看起来"正常"，但图标没了，只剩空格。

**这就是本项目所有图标都写成 `\uXXXX` 转义的原因**：

```jsonc
"format": "  {usage}%"     // ✅ 纯 ASCII，任何环节都不会损坏
"format": "  {usage}%"          // ❌ 直接贴字形，可能被吃掉
```

改配置时请保持这个写法。自查命令：

```bash
python3 -c "s=open('$HOME/.config/waybar/config.jsonc').read(); \
            print('PUA 字符数:', sum(1 for c in s if 0xE000<=ord(c)<=0xF8FF))"
```

输出应为 `0`。非 0 说明文件里混进了字面字形，虽然能用，但分享出去可能损坏。

**情况 B：字体没装好**

```bash
fc-list | grep -i "nerd"          # 有没有 Nerd Font
fc-match "Hack Nerd Font"         # 能不能被解析到
fc-cache -f ~/.local/share/fonts  # 刷新缓存
```

### 某个模块整个消失，日志报 `argument not found`

含义是：**该占位符在你的 waybar 版本里不存在**，整个模块会拒绝渲染。

已被证实会踩雷的占位符（在 waybar 0.15 上实测）：

| 模块 | ✅ 可用 | ❌ 不支持 |
|---|---|---|
| `cpu` | `{usage}` `{avg_frequency}` `{max_frequency}` `{icon}` | `{load1}` `{load5}` `{load15}` |
| `memory` | `{percentage}` `{used}` `{total}` `{avail}` | `{free}` `{swap_used}` `{swap_total}` |

不同 waybar 版本支持情况可能不同。**排查方法**——逐个占位符单独试：

```bash
cat > /tmp/t.jsonc <<'EOF'
{ "layer":"overlay","position":"bottom","height":10,"modules-center":["cpu"],
  "cpu": { "interval": 1, "format": "{load1}" } }
EOF
timeout 4 waybar -c /tmp/t.jsonc 2>&1 | grep "argument not found"
```

有输出就说明这个占位符不支持，删掉它即可。

> 不要用 `strings waybar | grep 占位符` 来判断——这个方法会给出**假阳性和
> 假阴性**（实测把在用的 `battery` 判成不存在，把不支持的 `load1` 判成存在）。

### 模块内容不显示，日志报 `不是有效的名称` / markup 错误

**`format` 串里不能出现 `<` `>` 尖括号。** Waybar 的文本走 Pango markup 渲染，
尖括号会被当成 HTML 标签。

```jsonc
"format": "MEM <{used}G>"        // ❌ 触发 markup 解析错误
"format": "MEM &lt;{used}G&gt;"  // ✅ 用 HTML 实体转义
```

### 工作区的 一~十 显示成方块

缺中日韩字体：

```bash
sudo apt install fonts-noto-cjk
fc-match "Noto Sans CJK JP"
```

不想要汉字的话，把 `config.jsonc` 里 `hyprland/workspaces` 的 `format-icons`
换成普通数字即可。

### 点击图标没反应

逐个检查依赖命令在不在：

```bash
for c in pavucontrol nm-connection-editor gnome-system-monitor wlogout wl-copy nmcli wpctl; do
    command -v "$c" >/dev/null && echo "✓ $c" || echo "✗ $c 缺失"
done
```

### 网络设置点了「保存」没反应，也不报错

**缺 polkit 认证代理。** 这是 Hyprland 新用户最容易踩的坑：
GNOME / KDE 桌面自带代理，Hyprland **不会**自动拉起任何代理。

```bash
sudo apt install lxpolkit
```

然后在 `~/.config/hypr/hyprland.conf` 加：

```
exec-once = lxpolkit
```

详见 `hyprland/hyprland.conf.snippet`。

> **另一个隐藏的坑**：如果你装的是 `hyprpolkitagent`（Hyprland 官方代理），
> 它自带一个 systemd 用户服务。但该服务的
> `WantedBy=graphical-session.target`，而 Hyprland 默认**不会激活**
> `graphical-session.target`——所以 `systemctl --user enable hyprpolkitagent`
> 是无效的，必须从 Hyprland 启动时显式 `start`。

### 磁盘模块一直显示 0B

`diskio.sh` 靠 `/proc/diskstats` 里的设备名匹配。如果你用的是
**btrfs 子卷**，`findmnt` 会返回 `/dev/nvme0n1p7[/@]` 这种带方括号的形式，
解析时**必须剥掉 `[/@]` 后缀**，否则设备名会变成 `@]`，什么都读不到。
本项目的脚本已处理，手动改写时请留意。

排查：

```bash
findmnt -no SOURCE /          # 看根分区返回什么
bash -x ~/.config/waybar/scripts/diskio.sh   # 跟踪执行过程
```

### 悬停时阴影是瞬间变化，没有过渡动画

GTK 的限制，不是配置错误。GTK3 的 `transition` 只对
`background-color` / `color` / `border-color` 生效，
**`box-shadow` 和 `border-radius` 不参与过渡**。

### 想实时看日志

```bash
waybar -l debug
```

配置和 CSS 存盘即热重载，不用重启。手动重载：

```bash
pkill -SIGUSR2 waybar
```

---

## 目录结构

```
waybar/
├── install.sh                     # 安装脚本（含 --uninstall）
├── README.md
├── config/                        # 会被部署到 ~/.config/waybar/
│   ├── config.jsonc               # 模块配置（图标为 \uXXXX 转义）
│   ├── style.css                  # 样式
│   └── scripts/
│       └── diskio.sh              # 磁盘读写速率（读 /proc/diskstats）
└── hyprland/                      # 可选的 Hyprland 侧配置片段
    ├── hyprland.conf.snippet      # 标准 conf 写法
    └── hyprland.lua.snippet       # Lua 配置写法
```

## 卸载

```bash
./install.sh --uninstall
```

当前的 `config.jsonc` / `style.css` 会被改名为 `*.removed-<时间戳>` 保留，
并询问你是否还原安装时的备份。

## 已知限制

- 在 Waybar **0.15** (Arch/Manjaro) 上完整实测过；
  **Ubuntu 侧的 waybar 0.11~0.13 未逐项验证**，
  部分占位符支持情况可能不同（见「常见问题」）
- 硬盘图标不区分 SSD / HDD
- 磁盘读写只监控根分区所在的那块物理盘（可用 `WAYBAR_DISK` 覆盖）

## 许可

MIT
