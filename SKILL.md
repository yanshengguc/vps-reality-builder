---
name: vps-reality-builder
description: 云 VPS 搭建 + VLESS Reality 代理节点部署全流程技能。覆盖 Azure/GCP/任意 Ubuntu VPS:CLI 登录、创建 VM、双层防火墙(NSG+ufw)、Xray Reality 443 部署、客户端 vless 链接与二维码生成、连通性诊断。当用户提到"搭 VPS/建服务器/开云主机/搭节点/Reality/xray/v2rayN 节点/科学上网服务器/美国节点/日本节点/检查 IP/端口不通"等任何涉及购买或配置云服务器做代理的场景时,必须使用本技能,即使用户没有明说"Reality"或"代理"字样。也适用于已部署节点出问题时的排查(端口不通、连不上、IP 被墙)。
---

# VPS Reality Builder

从零把一台云 VPS 变成 VLESS Reality 代理节点,并输出可直接导入 v2rayN/v2rayNG 的配置。全流程 CLI 驱动,用户只负责账号登录和最终验收。

## 铁律(先读这个)

1. **绝不用浏览器自动化操作云门户**。本机环境拉起的浏览器窗口用户看不到(渲染正常但 GUI 不显示),用户没法在里面登录。一律走 CLI + 设备码登录,登录动作(密码/MFA)永远由用户本人完成,AI 不碰凭据。
2. **节点密钥绝不外泄**。UUID/私钥/分享链接只写入用户本地文件(如 `vless-node-info.md`),不打印到无关日志、不提交任何仓库、不放进记忆文件。
3. **改 xray 配置前必须 `-test` 校验,失败立即用 `.bak` 回滚**。用户现有节点往往在跑,服务中断是事故。
4. **新增 inbound 共存,不删旧配置**——用户的旧节点可能还在用。
5. 破坏性操作(删 VM/删资源组/重置配置)先向用户确认。
6. 冗余输出重定向到文件,控制 token 消耗;SSH 命令用脚本文件 `ssh 'bash -s' < script.sh` 传递,避免嵌套引号地狱。

## 流程总览

```
① 选云 → ② CLI 登录(设备码) → ③ 建 VM + 开端口 → ④ SSH 部署 Reality
→ ⑤ 端到端验证 → ⑥ 生成客户端配置(链接+二维码) → ⑦ 用户双端验收
```

### ① 选云(先问清用户的"地区"需求)

| 云 | 学生额度 | 区域限制 | 适用 |
|---|---|---|---|
| Azure for Students | $100/年 | **有系统区域白名单**,美国区全封死 | 亚太节点(日/韩/新/马/印尼) |
| GCP 免费试用 | $300/90天,无需学生认证,绑卡即得 | 无 | **美国节点首选** |
| DigitalOcean(学生包) | $200/1年 | 无 | 备胎 |
| 任意裸 VPS | - | 无 | 通用 |

**Azure 区域白名单是订阅级系统策略,用户改不了,别浪费时间试**。查询方法见 [references/azure.md](references/azure.md)。用户要美国 IP 时直接推荐 GCP。提醒用户:订阅 ChatGPT、谷歌商店、GitHub 等**不需要美国 IP**(日韩新加坡均支持),先确认真实需求再选区,能省一半延迟。

### ② CLI 登录(参考各云 reference)

- Azure:`az login --use-device-code`,设备码 15 分钟过期,过期就重发,让用户"输完码走到显示已登录为止"。
- **Windows 沙箱坑**:bash 沙箱写 `~/.azure` 会被拒(报 FileNotFoundError 但目录实际存在)。解法:`AZURE_CONFIG_DIR` 指向工作区目录,如 `.workbuddy/azconfig`,所有 az 命令都带这个环境变量(建议写 wrapper 脚本)。
- GCP:`gcloud auth login --no-launch-browser`。

### ③ 建 VM + 防火墙

标准配置:Ubuntu 24.04 LTS、SSH 密钥登录(专用新密钥,如 `~/.ssh/id_ed25519_<cloud>`)、独立安全组。
**防火墙是两层的**:云安全组(NSG/防火墙规则)+ 系统内 ufw。两层都要放行所需端口(典型 22/443)。见 [references/troubleshooting.md](references/troubleshooting.md) 的"443 连不通"诊断顺序。

### ④ 部署 Reality(核心脚本 `scripts/deploy_reality.sh`)

前置检查:服务器上已有 xray 则直接复用二进制;没有则先装(官方安装脚本)。然后:

1. 测候选 SNI 伪装站(要求 TLS1.3 + h2),选与服务器**地理/品牌合理**的大站(首尔机配 samsung.com 是范例)
2. 生成 UUID / x25519 密钥对 / shortId
3. **合并**新 443 Reality inbound 进现有 config.json(保留旧 inbound),改前自动备份
4. `xray -test -config` 校验 → `systemctl restart xray` → 确认新旧端口都在监听

**关键坑:Xray 26.x 的 `xray x25519` 输出格式是 `PrivateKey: xxx` 和 `Password (PublicKey): xxx`(冒号后无空格、字段名带空格变化),解析必须用 `awk -F': *' '{print $2}'` 兜底,拿到空值就是事故**(会导致配置校验失败、服务中断)。脚本已内置健壮解析。

### ⑤ 端到端验证(部署完必做,按顺序)

```bash
# 1. 云外 TCP 可达(从本地跑,不是服务器上跑)
python -c "import socket;s=socket.socket();s.settimeout(8);s.connect(('<IP>',443));print('OPEN')"
# 2. 伪装验证:看到的必须是伪装站真证书
echo | openssl s_client -connect <IP>:443 -servername <SNI> 2>/dev/null | grep -E 'subject=|TLSv1.3'
```

不通就按 troubleshooting 的三层顺序查:云安全组 → ufw → 网络路径/GFW。

### ⑥ 客户端配置(`scripts/gen_client_config.py`)

生成三件套到工作区:`vless://` 分享链接(v2rayN 粘贴导入)、二维码 PNG(v2rayNG 扫码)、参数明细 Markdown(含服务器 SSH 信息与变更记录,文件头标注"仅限本人,勿外传勿提交")。二维码依赖 `qrcode` 库(装在隔离 venv)。

### ⑦ 用户验收清单

电脑 v2rayN 导入链接选为活动节点;手机 v2rayNG 扫码;验证 Google Play、ChatGPT、GitHub、YouTube 4K。卡在订阅支付时提醒:国内卡直付 OpenAI 常被 Stripe 拒,走 iOS 应用内订阅。

## Reference 索引(按云读取,不要全读)

- [references/azure.md](references/azure.md) — az wrapper、设备码登录、AZURE_CONFIG_DIR 沙箱坑、区域白名单查询、vm create/NSG 完整命令
- [references/gcp.md](references/gcp.md) — gcloud 安装登录、e2-micro 免费层、美国区建机、防火墙规则、出站流量计费提醒
- [references/troubleshooting.md](references/troubleshooting.md) — 443 连不通三层诊断、x25519 解析、设备码过期、节点 IP 被墙判断与换 IP
