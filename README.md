# Snell v5 / v6 多实例配置管理面板

面向 Debian / Ubuntu 的 Snell 安装与配置管理脚本。Snell v5 和 v6 使用完全独立的二进制、配置、端口、PSK、systemd 服务、日志及备份，可以在同一台服务器上同时运行。

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/mikuuu3981/snell-click/main/snell.sh -o /tmp/snell.sh && sudo bash /tmp/snell.sh
```

首次打开主面板会自动注册 `/usr/local/bin/snell` 短命令，以后直接运行 `sudo snell` 即可。也可以在脚本目录运行 `sudo ./snell.sh register-command` 手动注册或更新短命令。

主面板会同时显示 v5 和 v6 的状态，并可直接进入对应实例。每个实例的常用操作按安装、客户端、配置、服务、日志与维护分组；配置页只保留端口、PSK 和 IPv6，高级选项单独收纳，脚本会为两个实例选择不同的可用端口。

安装时会提示输入监听端口；也可以使用 `snell v6 install 23606` 或 `SNELL_PORT=23606 snell v6 install` 直接指定。留空则自动选择 `20000-40000` 之间的可用端口。重装时留空会保留当前端口，也可以输入新端口。脚本会在写入配置前验证端口范围并检查 TCP/UDP 占用。

交互面板会在终端中使用颜色区分运行状态、普通操作、升级和危险操作；所有菜单都可以按 `q` 返回上一级，主菜单按 `q` 退出。设置 `NO_COLOR=1` 可以关闭颜色输出。

v5 默认采用官方向导一致的 IPv4 监听，v6 默认启用 IPv4/IPv6 双栈。两个实例都可以在配置菜单中单独调整 IPv6。

防火墙要求：

- Snell v5 使用 TCP 和 QUIC，需要同时放行对应端口的 TCP、UDP。
- Snell v6 使用 TCP，需要放行对应端口的 TCP。

## 实例隔离

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

- 独立安装、重装、更新和卸载 v5 或 v6
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
- 面板设置中注册短命令并检查、升级管理脚本

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

## 管理面板升级

从主菜单进入“面板设置 / 升级”，选择“检查并升级管理面板”；也可以直接运行：

```bash
sudo snell self-update
```

升级过程会先下载到临时文件，验证脚本身份和 Bash 语法后再原子替换 `/usr/local/bin/snell`。升级完成后退出当前面板并重新运行 `snell` 即可使用新版。该操作不会修改 Snell v5/v6 的服务端程序、配置、端口、PSK、服务或备份。同一版本重复检查只会提示当前已是最新版本。

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

服务使用 `nobody:nogroup` 运行。配置文件归属为 `root:nogroup`、权限为 `640`；备份目录和备份文件分别使用 `700` 和 `600`。每次修改配置前自动备份，重启失败则恢复旧配置。

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

仓库包含单实例回归测试和双实例共存测试，不会访问真实 systemd 或 `/etc`：

```bash
./tests/snell_test.sh
./tests/coexist_test.sh
./tests/menu_test.sh
shellcheck snell.sh tests/*.sh tests/fixtures/*
```
