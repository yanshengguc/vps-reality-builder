# VPS Reality Builder

> **VLESS + Reality 部署 | Xray | Azure / GCP / Cloady | v2rayN / v2rayNG 客户端排查**
>
> 一个 AI Agent 可执行的云服务器搭建技能:从零把一台云主机(或免费容器)变成 VLESS 节点,并输出可直接导入 v2rayN / v2rayNG 的客户端配置。全流程 CLI 驱动,沉淀了实战中踩过的全部坑。
>
> **给谁用:任何支持 Agent Skill 的普通 AI 助手。** 把技能装给你的 AI 助手之后,你只需要做三件事:① **注册账号**(按助手给的链接去云平台注册) ② **回答需求**(助手提问:要哪个地区、干什么用、要不要长期用) ③ **最终验收**(在自己手机/电脑上连上节点,确认能用)。剩下的选云、登录、建机、部署、验证、排查,全部由 Agent 做。账号密码、验证码永远由你本人操作,Agent 不碰凭据。

> **⚠️ 免责声明(使用前必读)**
>
> 本项目**仅供网络协议学习、个人服务器运维自动化研究使用**。
>
> 1. 本项目**不提供、不运营、不代理任何服务器或节点服务**,仓库中不含任何真实服务器地址、密钥或可用配置。文中所有 IP、域名、密钥均为占位示例。
> 2. 你使用本项目所做的一切操作(购买云资源、部署软件、修改系统配置)产生的**费用、数据丢失、账号封禁、法律风险,均由你本人自行承担**。执行任何删除/重置类破坏性操作前,请自行确认并备份。
> 3. 请确保你的使用行为**符合你所在国家/地区的法律法规**以及云服务商的服务条款。是否允许搭建代理、允许的用途范围,各地规定不同,请自行了解并遵守;因违规使用导致的任何后果与本仓库作者无关。
> 4. 本项目按"现状"提供,**不附带任何明示或默示的担保**。作者不对代码的准确性、稳定性、适用性作任何承诺,亦不对因使用或滥用本项目造成的任何直接或间接损失负责。
> 5. 本项目与 Microsoft Azure、Google Cloud、DigitalOcean、Xray 项目及文中提到的任何网站/品牌**均无隶属或合作关系**,提及的名称仅作技术说明。
> 6. 请勿将本项目用于任何商业转售、攻击、扫描、破坏他人系统等非法或侵权用途。
>
> **继续下载/使用即视为你已阅读、理解并同意上述全部条款。**

---

## 两条部署路线(按需选一条)

| 路线 | 适合 | 费用 | 延迟 | 入口 |
|---|---|---|---|---|
| **VPS + Reality 443 直连** | 追求最低延迟、长期用 | 按云厂商免费层/学生额度 | 最低 | `scripts/deploy_reality.sh` |
| **免费容器 + WS + TLS** | 不要钱、快速上线 | Cloady 永久免费档 $0/月 | 经平台转发,略高 | `scripts/gen_cloady_ws.sh` |

已确认跑通(2026-11-05 用户确认):AWS、Azure、Cloady 免费容器。

学生优先 Azure for Students($100/年,不绑卡);非学生优先 GCP $300 试用或 AWS $200 额度(都要绑卡),不想绑卡选 Cloady $0。

## 快速开始

```bash
# 路线一:VPS Reality(需一台 Ubuntu 24.04,见 references/azure.md 或 references/gcp.md 建机)
bash scripts/deploy_reality.sh

# 路线二:Cloady 免费容器(邮箱注册,不绑卡,区域 usw1)
bash scripts/gen_cloady_ws.sh ./xray-deploy
# 再把生成的三个文件上传到 Cloady 部署,详见 references/cloady.md

# 路线三:手动部署(不用 Agent,照着部署文件自己走)
# Cloady 见 references/cloady.md

# 客户端配置三件套(vless 链接 / 二维码 / 参数明细)
python3 scripts/gen_client_config.py
```

详细的执行规范见 [SKILL.md](SKILL.md)(面向 AI Agent 编写,人类读者把它当流程文档看也完全可以)。

## 目录结构

```
vps-reality-builder/
├── SKILL.md                        # Agent 技能主文件:铁律 + 七步流程
├── README.md                       # 本文件
├── scripts/
│   ├── deploy_reality.sh           # Reality 部署脚本(密钥生成/配置合并/校验/回滚)
│   ├── gen_cloady_ws.sh            # Cloady 部署文件一键生成(Dockerfile + compose + config)
│   └── gen_client_config.py        # 客户端三件套生成:vless 链接 / 二维码 / 参数明细
└── references/
    ├── aws.md                      # AWS:新老账号免费档区别、SSO/密钥登录、安全组命令、账单告警
    ├── azure.md                    # az CLI wrapper、设备码登录、区域限制策略、NSG 命令、换公网 IP
    ├── gcp.md                      # gcloud 登录、e2-micro 免费层、防火墙规则
    ├── cloady.md                   # Cloady 免费档核实、邮箱验证码注册、多阶段 Dockerfile、WS+TLS 验证
    ├── oracle.md                   # Oracle Cloud:oci CLI、API 密钥/会话令牌、新加坡首选,免费档建机待实测
    ├── troubleshooting.md          # 端口不通三层诊断、x25519 解析坑、卡顿诊断、IP 被墙判断
    └── v2rayn-client.md            # v2rayN 客户端:配置地图、TUN/全局/分流判定、DNS 走代理陷阱
```

## 它解决什么问题

手动搭一台 Reality 节点不难,难的是细节全对:

- **防火墙有两层**:云安全组(NSG)+ 系统内 ufw,只开一层端口照样不通。本项目固化了「云安全组 → ufw → 网络路径」的三层诊断顺序。
- **Xray 26.x 的 `x25519` 输出格式变了**(`PrivateKey:` 冒号后无空格、字段名带空格变化),脚本解析不当会拿到空私钥 → 配置校验失败 → **服务中断**。`deploy_reality.sh` 内置健壮解析,且遵循「改前备份、`-test` 校验、失败回滚」原则。
- **共存而非替换**:新增 443 inbound 时不删旧配置,不影响已在跑的旧节点。
- **云厂商差异**:Azure 学生订阅存在系统级区域白名单(用户不可改),GCP 无区域限制且免费层覆盖美国区——选区建议直接写在技能里。
- **能连不等于用着快**:客户端开了 TUN + 全局,国内流量也会绕境外;更隐蔽的是 Xray 的 DNS 模块查询全部经代理发出,国内域名被解析成海外 CDN,`geosite:cn` 直连规则形同虚设(实测百度 2109ms,比 Google 的 765ms 还慢)。
- **IP 被封不等于要重装**:三步定性(端口矩阵 / 境外回连 / 路由),换 IP 时服务端一行都不用改,但必须同步移除明文 inbound,否则新 IP 会以同样方式再被封。
- **免费容器平台的坑**:官方 xray 镜像没有 shell,必须多阶段构建把二进制拷进 Alpine;平台默认服务端口 3000;WS 路径返回 HTTP 400 即在线,不是故障(2026-11-05 Cloady 实测)。

## 快速了解流程

```
① 选云 → ② CLI 登录(设备码) → ③ 建 VM + 双层防火墙
→ ④ SSH 部署 Reality → ⑤ 端到端验证 → ⑥ 生成客户端配置 → ⑦ 用户双端验收
```

部署完之后的三类运维场景也写进去了:**节点卡顿**(先分清跨境丢包 / 全局模式 / DNS 解析错误)、**IP 被封**(三步定性 + 换 IP)、**客户端分流不生效**(TUN 与 DNS 出口)。

## 常见报错速查

| 现象 | 原因 | 查哪里 |
|---|---|---|
| `xray -test` 校验失败,私钥为空 | Xray 26.x `x25519` 输出格式变了,解析拿到空值 | `references/troubleshooting.md` |
| 服务 active 但外网连不上 443 | NSG/安全组没放行,或 ufw 只开了一层 | 三层诊断:云安全组 → ufw → 网络路径 |
| Hysteria2 跑了一个月一直不通 | NSG 从未放行 UDP 443,服务空跑 | 同上,先看 NSG |
| 能连但国内网站比国外还慢 | DNS 查询全走代理,国内域名解析成海外 CDN | `references/v2rayn-client.md` |
| 部署后 WS 路径返回 HTTP 400 | **正常现象**,xray 对非 WS 请求的响应,即服务在线 | `references/cloady.md` |
| Cloady 部署报 `payment_required` | 超出免费档(0.5 vCPU / 1GB / 5GB)或免费档被占用 | 缩小配置,不要绑卡硬上 |

## 安全设计

- 凭据零接触:登录一律走设备码,人类本人完成认证,AI 全程不接触账号密码/MFA。
- 敏感信息闭环:节点 UUID / 私钥 / 分享链接只写入用户本地文件,工具内置「勿外传、勿提交」标注,不入库、不进日志、不进任何版本管理。
- 本仓库不含任何真实节点信息,复制使用时也请遵守同一原则。

## 适用读者

- 想理解 VLESS + Reality 协议在实际部署中长什么样的人
- 需要 API/CLI 全流程自动化管理自己云服务器的人
- 在给 AI Agent(如 WorkBuddy / Claude Code)编写技能/工具包的人——本仓库本身就是一个可直接安装的 Agent Skill 示例

## License

[MIT](LICENSE)
