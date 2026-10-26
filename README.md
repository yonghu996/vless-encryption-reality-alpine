# VLESS Encryption + REALITY + Vision (Alpine / Linux)

基于 Xray-core 的 VLESS Encryption（ML-KEM-768）+ REALITY + Vision 部署及管理脚本。

## Alpine Linux 快速部署

以 root 身份运行（需要有可用的公网网络）：

```sh
apk add --no-cache bash curl jq
curl -fsSL https://raw.githubusercontent.com/yonghu996/vless-encryption-reality-alpine/main/install.sh -o /root/xray-menu.sh
bash /root/xray-menu.sh
```

选择 **1**，填写端口、UUID（留空自动生成）、SNI 和 Short ID。完成后使用菜单 **8** 查看客户端链接；也可以运行以下命令检查：

```sh
rc-service xray status
rc-service xray checkconfig
netstat -lnt | grep ':12345'
```

最后一个命令中的 12345 请替换为自己设置的端口，同时在主机防火墙或云厂商安全组允许相应的 TCP 入站流量。

## sing-box 1.13.11 普通 VLESS 节点（不启用 VLESS Encryption）

现有加密节点默认保留。新版主菜单选择 **9** 创建独立的普通 VLESS + REALITY + Vision 入站（推荐使用不同端口，例如原 12773、新 12774）；菜单 **8** 查看所有节点链接。已有配置会先备份，新增配置校验失败时不会覆盖原节点。

```sh
bash /root/xray-menu.sh install --mode standard --port 12774 --sni bing.com
```

普通节点的服务端 `settings.decryption` 必须是 `"none"`，分享链接为 `encryption=none`，不包含 ML-KEM-768 公钥；原有加密节点不变。导出的普通节点链接保存在 root 家目录的 `xray_standard_端口.txt`。导出仍包含节点凭据，请勿公开传播。

**重要：** 目前菜单 1 和 7 仍是针对原加密节点的维护操作，会替换整个配置，可能删除追加的普通节点。为保留全部入站，请只使用菜单 9 新增普通节点，切勿通过菜单 1/7 维护混合配置；此限制将在后续版本解除。

## 无交互安装

```sh
apk add --no-cache bash curl jq
curl -fsSL https://raw.githubusercontent.com/yonghu996/vless-encryption-reality-alpine/main/install.sh -o /root/xray-menu.sh
bash /root/xray-menu.sh install --port 12345 --sni www.sega.com
```

默认随机生成 UUID；也可增加 `--uuid '自定义UUID'`、`--short-id 20220701` 和 `--quiet`。

**注意：SNI 输入域名时不要加反斜杠**，例如 `www.sega.com`，而不是 `www\\.sega.com`。

## 管理

重新运行 `bash /root/xray-menu.sh`，提供更新、启动/重启、停止、卸载、日志、修改配置及订阅查看菜单。安装时配置文件写入 `/usr/local/etc/xray/config.json`，客户端链接等信息存放在 root 的家目录。

在 Alpine 上使用 OpenRC 管理 Xray，自动设置开机启动；卸载会删除 Xray 程序、配置及日志，必须手动输入 `yes` 确认。修改配置会重新生成 VLESS Encryption 及 REALITY 密钥，旧客户端链接将失效。

## 发布说明（Releases）

每次版本升级须同步修改 `SCRIPT_VERSION`、新增 `releases/vX.Y.Z.md` 更新说明，并推送同名 `vX.Y.Z` Git 标签。仓库内的 `.github/workflows/release.yml` 将自动执行测试，测试通过后发布 [GitHub Releases](https://github.com/yonghu996/vless-encryption-reality-alpine/releases)。不要仅修改 README 而不发布对应 Release。

## v1.8.2 — sing-box 1.13.x REALITY 兼容服务

- 普通 VLESS 节点使用独立的 Xray v25.9.11 服务与 OpenRC 服务 `xray-standard`，避免改变主 Xray 核心。
- 菜单 9 会迁移此前写入主配置的普通节点，尽可能保留凭据；菜单 8 从独立配置读取普通节点。
- 兼容服务使用独立配置、日志和二进制。端口冲突时拒绝迁移，主节点配置有备份。
- 需在真实 Alpine 与 sing-box 1.13.11 环境完成连接验收后，才能确认兼容性。

## v1.8.1 — 节点列表修复

- 修复菜单 8 中 Bash 变量转义导致普通节点无法显示的问题；不改变已建节点。
- 新增节点后尝试提示 TCP 端口监听情况。

## v1.8.0 — sing-box 兼容模式

- 增加不带 VLESS Encryption 的普通 VLESS + REALITY + Vision 入站。
- 支持菜单 9 和命令行 `--mode standard`，保留已有加密节点并使用独立端口。
- 客户端分享链接 `encryption=none`，自动保存普通节点的公钥信息；菜单 8 展示两种节点。
- 新增 `tests/test_standard_vless.sh` 回归测试。已进行静态和配置结构校验，真实 Alpine 服务与 sing-box 端到端握手尚待验收。

## v1.7.5 修复

- 修复 OpenRC 启动时 `/var/log/xray/error.log: permission denied`；使用 Xray 专用用户进行配置检查，并修复旧日志文件属主和权限。
- 菜单 3 现在先恢复日志权限再启动现有节点，无需重新下载 Xray 或生成新密钥。
- 迁移已弃用的 `freedom.domainStrategy` 到 `sockopt.domainStrategy`。

## v1.7.4 修复

- 解决 Xray `unsupported config file extension`：临时配置文件保留 `.json` 后缀。
- 为临时文件扩展名新增检查，并配置标签触发的 GitHub Releases 自动发布流程。
- 历史更新记录存放在 `releases/` 文件夹。

## v1.7.3 修复

- 兼容 Xray 26.10.21 的 `Password (PublicKey):` REALITY 公钥标签，同时保留对旧标签的支持。
- 对密钥输出执行格式校验，异常情况明确失败而非写入损坏配置。
- 临时配置检查显式指定 `-format=json`（仅指定格式不足以解决临时文件扩展名问题，已在 v1.7.4 修复）。
- 增加 `tests/test_reality_keys.sh` 回归测试，用法：`bash tests/test_reality_keys.sh`。

## v1.7.2 修复

- 将已失效的 `install-geodata` 更改为官方 `update-geodata`。如果扩展 Geo 数据下载失败，保留内置 Geo 数据，不中断节点安装。
- 修复首次安装后启动、开机自启、OpenRC 状态检查和停止服务。
- Alpine 专用卸载方式及日志菜单，适配官方安装器不支持的 `remove` 操作。
- 新增 UUID、端口、SNI、Short ID 校验；配置通过 Xray 检查后才替换现有文件。
- 加强配置和客户端信息的文件权限（配置 `root:xray 0640`，客户端文件 `0600`）。
- 增加 `pipefail`，避免官方安装器下载失败被误判为成功。

## 重要提示

此项目的 VLESS Encryption 功能对客户端内核版本有要求，请使用支持相应协议及 REALITY/Vision 的 Xray 客户端。**目前已进行源代码审阅；仍需在真实 Alpine 主机上完成联网端到端测试。**

依赖上游：[XTLS/Xray-core](https://github.com/XTLS/Xray-core)、[XTLS/Xray-install](https://github.com/XTLS/Xray-install)。
