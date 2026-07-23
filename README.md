# 多核心代理配置管理面板

面向 Debian / Ubuntu 的代理核心安装与配置管理脚本。目前支持 Snell 和 Xray，并按“核心 → 实例/操作”组织菜单，后续可以继续加入其他核心而不扩张顶层导航。

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/mikuuu3981/snell-click/main/snell.sh -o /tmp/snell.sh && sudo bash /tmp/snell.sh
```

首次打开主面板会自动注册 `/usr/local/bin/snell` 短命令，以后直接运行 `sudo snell` 即可。也可以在脚本目录运行 `sudo ./snell.sh register-command` 手动注册或更新短命令。

主面板只显示每个核心的一行摘要，入口固定为“Snell 管理”“Xray 管理”和“检查面板更新”。Snell 未安装时会在安装流程中选择 v5 稳定版或 v6 Beta；只存在一个 Snell 版本时会直接进入该实例，只有兼容已有双实例安装时才显示 v5/v6 选择页。

安装时会提示输入监听端口；也可以使用 `snell v6 install 23606` 或 `SNELL_PORT=23606 snell v6 install` 直接指定。留空则自动选择 `20000-40000` 之间的可用端口。重装时留空会保留当前端口，也可以输入新端口。脚本会在写入配置前验证端口范围并检查 TCP/UDP 占用。

交互面板会在终端中使用颜色区分运行状态、普通操作、升级和危险操作；所有菜单都可以按 `q` 返回上一级，主菜单按 `q` 退出。设置 `NO_COLOR=1` 可以关闭颜色输出。

v5 默认采用官方向导一致的 IPv4 监听，v6 默认启用 IPv4/IPv6 双栈。Snell v6 当前仍处于 Beta 阶段，安装页和状态页会明确标注；Beta 期间可能出现协议不兼容变更，应同步更新服务端和 Surge 客户端。

防火墙要求：

- Snell v5 使用 TCP 和 QUIC，需要同时放行对应端口的 TCP、UDP。
- Snell v6 使用 TCP，需要放行对应端口的 TCP。

## Snell 管理

首次进入“Snell 管理”后选择安装版本：

- Snell v5：稳定版，支持 TCP 和 QUIC。
- Snell v6：Beta，使用 TCP，支持部署级协议特征多样化和新的网络栈选项。

安装完成后，Snell 管理页提供客户端配置、端口、PSK、IPv6、高级配置、服务、日志、备份、诊断、内核更新和卸载。v5/v6 后端资源仍保持隔离，以兼容此前允许双实例共存的版本；新菜单不会把双实例作为默认工作流。

### Snell 资源隔离

两个版本的默认资源如下：

| 资源 | Snell v5 | Snell v6 |
| --- | --- | --- |
| 二进制 | `/usr/local/bin/snell-server-v5` | `/usr/local/bin/snell-server-v6` |
| 配置 | `/etc/snell/v5/snell-server.conf` | `/etc/snell/v6/snell-server.conf` |
| 备份 | `/etc/snell/v5/backups/` | `/etc/snell/v6/backups/` |
| 服务 | `snell-v5.service` | `snell-v6.service` |
| 默认版本 | `v5.0.1` | `v6.0.0rc` |

修改、重启、更新或卸载一个实例不会改动另一个实例。两个实例不能监听相同端口，脚本会在安装和端口修改时检查 TCP、UDP 占用。

## 面板功能

- 按核心收敛的 Snell、Xray 和面板更新顶层导航
- 在 Snell 安装时选择 v5 稳定版或 v6 Beta
- 独立安装、更新 Snell 内核和卸载 v5/v6；命令行保留重装能力用于修复
- 安装向导中主动指定端口，或留空自动选择可用端口
- 双实例状态概览及单实例详细运行状态
- 修改端口、PSK、IPv6、自定义 DNS、DNS IP 偏好和出口网卡
- 管理 v6 的 `default`、`unshaped`、`unsafe-raw` 运行模式
- 分别生成 `version=5` 和 `version=6` 的 Surge、mihomo 配置
- 独立启动、停止、重启服务及管理开机自启
- 查看各实例最近日志或实时跟踪日志
- v5 TCP/UDP 与 v6 TCP 监听诊断
- 手动备份、自动变更前备份和一键恢复
- 配置启动失败时自动回滚
- 服务端更新失败时自动恢复旧二进制
- 安装、更新、校验、启停、日志和卸载 Xray 核心
- 创建和管理多个 VLESS TCP REALITY Vision 入站及用户
- 生成 VLESS 分享链接和 Mihomo / Clash Meta 客户端配置
- Xray 更新前使用新核心校验现有配置，启动失败时恢复旧核心和 Geo 数据
- 打开面板时自动注册或修复短命令，顶层菜单可直接检查并升级管理脚本

状态页只显示脱敏 PSK。完整 PSK 仅在客户端配置页和主动修改 PSK 后显示。

## 命令行管理

在命令前添加 `v5` 或 `v6` 选择实例；省略时保持向后兼容，默认管理 v6。

```bash
sudo snell status-all

sudo snell v5 install
sudo snell v6 install
# 也可以直接指定监听端口；安装前会检查 TCP/UDP 占用
sudo snell v6 install 23606

sudo snell v5 status
sudo snell v6 status
sudo snell v5 client v5.example.com
sudo snell v6 client v6.example.com

sudo snell v5 set-port 23505
sudo snell v6 set-port 23606
sudo snell v5 set-psk
sudo snell v6 set-mode unshaped
sudo snell v5 restart
sudo snell v6 diagnose
sudo snell v5 update v5.0.1
sudo snell v6 update v6.0.0rc
```

其他配置命令 `set-ipv6`、`set-dns`、`set-dns-preference`、`set-egress`、`logs`、`backup` 和 `restore` 同样接受版本前缀。运行 `snell help` 查看完整列表。

## Xray 管理

Xray 支持核心生命周期管理，以及多个 VLESS TCP REALITY Vision 入站和用户。交互面板从“Xray 管理 → 入站管理”创建入站；创建时必须输入 SNI。端口留空时优先使用 `443`，如果 `443` 已被系统服务或现有托管入站占用，则使用 `8443`；两者都被占用时必须输入其他端口。官方 Xray 提示非 `443` REALITY 端口会增加服务器 IP 被封锁的风险，因此使用 `8443` 或其他端口时面板会明确警告，但不会阻止用户继续。

```bash
sudo snell xray status
sudo snell xray latest
sudo snell xray install
sudo snell xray update
sudo snell xray test
sudo snell xray restart
sudo snell xray logs 100
sudo snell xray inbounds
sudo snell xray reality-add www.example.com
sudo snell xray reality-add www.example.com 8443 user1
sudo snell xray reality-edit 1 cdn.example.com 9443
sudo snell xray reality-client 1 proxy.example.com
sudo snell xray user-add 1 alice
sudo snell xray user-delete 1 00000000-0000-4000-8000-000000000001
sudo snell xray reality-delete 1
sudo snell xray uninstall
```

每个入站使用独立的 REALITY X25519 密钥和 shortId，用户使用独立 UUID，并固定为 `xtls-rprx-vision` 流控。客户端页输出标准 VLESS URI 和 Mihomo / Clash Meta YAML；服务器地址可以使用自动检测到的公网 IPv4，也可以主动输入域名或 IP。SNI 应当是支持 TLS 1.3 的目标站点证书域名，不能输入 URL、路径或端口。

Xray `v26.7.11` 起，REALITY 服务端默认要求客户端支持 `26.3.27+` 握手。面板保留官方默认，不会自动设置 `minClientVer: 0.0.0` 降低防护；使用 Mihomo 时应选择已经适配该握手版本的构建，否则可能出现 authentication failed。客户端配置页会显示对应提醒。

面板只管理标签以 `snell-managed-vless-reality-` 开头的入站。修改配置时使用 `jq` 保留其他入站、出站、日志、DNS 和路由字段，不会删除用户手写内容。为避免破坏 JSONC 注释或非标准结构，自动管理只接受根对象中 `inbounds`、`outbounds` 为数组的严格 JSON；不符合条件时会拒绝修改，现有 Xray 服务仍可继续手动管理。

每次添加、修改、删除入站或用户时，脚本会先生成候选配置并执行 Xray 配置测试，然后将原配置以 `600` 权限备份到 `/usr/local/etc/xray/backups/`，再原子替换 `config.json`。运行中的服务会重启并检查状态；新配置启动失败时自动恢复旧配置。经由该 Xray 入站的 SSH 可能在重启时暂时断开，SSH 断线本身不代表配置操作失败，重新连接后可运行 `snell xray status` 和 `snell xray inbounds` 核验。

省略版本时通过 XTLS 官方 GitHub Release API 获取最新稳定版；也可以使用 `snell xray install v26.7.11` 或 `snell xray update v26.7.11` 固定版本。支持的 Linux 架构为 amd64、arm64 和 i386。

默认使用 Xray 官方标准路径：

| 资源 | 路径 |
| --- | --- |
| 核心 | `/usr/local/bin/xray` |
| 配置 | `/usr/local/etc/xray/config.json` |
| 配置备份 | `/usr/local/etc/xray/backups/` |
| Geo 数据 | `/usr/local/share/xray/` |
| 日志 | `/var/log/xray/` |
| 服务 | `/etc/systemd/system/xray.service` |

已有标准路径安装会被直接识别。首次安装且没有配置时，脚本只创建最小合法的 `{}` 配置并启动空核心，不会擅自创建协议入站；已有 `config.json` 始终保留。下载时会验证官方 `.dgst` 中的 SHA-256，更新前会用目标核心执行配置测试，替换后服务启动失败则恢复旧核心、`geoip.dat`、`geosite.dat` 和服务文件。卸载只移除核心、Geo 数据和服务，保留配置与日志。

## Snell 内核更新

进入任一已安装实例后，可以直接选择“更新 Snell 内核”。命令行用法为：

```bash
sudo snell v5 update
sudo snell v6 update
# 也可以明确指定目标版本
sudo snell v6 update v6.0.0rc
```

省略版本时使用管理脚本内置的对应版本。更新会保留配置、端口和 PSK，下载并替换服务端二进制，然后重启对应实例；如果新版本未能正常启动，脚本会自动恢复旧二进制和版本信息。

重启 Snell 时，经过该实例的现有连接可能中断。如果当前 SSH 本身经由正在更新的 Snell 实例，SSH 断线并不能单独证明更新失败；代理恢复后应重新连接并运行 `sudo snell v5 status` 或 `sudo snell v6 status` 核验。

## 管理面板升级

从主菜单选择“检查面板更新”；也可以直接运行：

```bash
sudo snell self-update
```

升级过程会先下载到临时文件，验证脚本身份和 Bash 语法后再原子替换 `/usr/local/bin/snell`。升级完成后退出当前面板并重新运行 `snell` 即可使用新版。该操作不会修改 Snell、Xray 的核心程序、配置或服务。同一版本重复检查只会提示当前已是最新版本。

## 旧版迁移

旧脚本使用以下单实例路径：

```text
/usr/local/bin/snell-server
/etc/snell/snell-server.conf
/etc/systemd/system/snell.service
```

新面板检测到旧实例后会显示迁移入口，也可以直接执行：

```bash
sudo snell migrate
```

脚本会从版本文件或二进制识别 v5/v6，保留原端口、PSK、高级配置和备份，然后迁移到对应独立实例。若新服务启动失败，迁移会被取消并恢复旧 `snell.service`。无法识别版本时可以明确指定：

```bash
sudo snell migrate v5
sudo snell migrate v6
```

## 配置与安全

Snell 和面板创建的 Xray 服务都使用 `nobody:nogroup` 运行。配置文件归属为 `root:nogroup`、权限为 `640`；Snell 和 Xray 的备份目录及文件分别使用 `700` 和 `600`。每次修改配置前自动备份，重启失败则恢复旧配置。

可以使用环境变量指定初始实例参数：

```bash
SNELL_PROTOCOL=v5 \
SNELL_VERSION=v5.0.1 \
SNELL_PORT=23505 \
SNELL_IPV6=false \
sudo -E snell install
```

默认版本也可以分别通过 `SNELL_V5_VERSION` 和 `SNELL_V6_VERSION` 覆盖。PSK 必须为 12-255 个字符；脚本默认生成 32 位随机十六进制 PSK。

## 验证

仓库包含 Snell 单实例、双实例兼容、菜单和 Xray 生命周期回归测试，不会访问真实 systemd 或 `/etc`：

```bash
./tests/snell_test.sh
./tests/coexist_test.sh
./tests/menu_test.sh
./tests/xray_test.sh
shellcheck snell.sh tests/*.sh tests/fixtures/*
```
