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
