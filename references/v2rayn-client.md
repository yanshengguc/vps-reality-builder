# v2rayN 客户端:TUN、分流与 DNS 排查

服务端搭得再好,客户端配错一样白搭。这一节全部来自 2026-10-30 的实机排查。

## 配置文件地图

v2rayN V7 便携版(`v2rayN-windows-64\`)目录结构:

```
guiConfigs\guiNConfig.json    # 设置项:TUN、路由索引、DNS 简版配置
guiConfigs\guiNDB.db          # sqlite:节点、路由预设、DNS 配置、统计
binConfigs\config.json        # 运行时 xray 配置(每次启动重新生成!)
bin\xray\xray.exe
bin\sing_box\sing-box.exe
bin\mihomo\mihomo.exe
guiLogs\                      # 运行日志
```

**关键**:`binConfigs\config.json` 是生成物,直接改无效,下次启动就覆盖。要改行为只能改 `guiNConfig.json` / `guiNDB.db`,或走 GUI。

进程路径拿不到时(V2rayN 以管理员运行时 `Get-Process` 的 Path 为空),用文件搜索定位:

```powershell
Get-ChildItem -Path "C:\","D:\" -Filter "v2rayN.exe" -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue |
  Select-Object -First 3 -ExpandProperty FullName
```

## 三种模式的实际差异

| | 系统代理·规则 | 系统代理·全局 | TUN |
|---|---|---|---|
| 捕获层 | 应用层(写入系统代理设置) | 同左 | 虚拟网卡 + 路由表 |
| 覆盖范围 | 只覆盖读系统代理的程序 | 同左,但规则全转发 | **全系统 TCP+UDP** |
| 命令行 npm/pip/git | 不走(读环境变量) | 不走 | 走 |
| 游戏 / UDP | 不走 | 不走 | 走 |
| UWP / 服务 | 不走 | 不走 | 走 |
| DNS | 看设置 | 看设置 | 走 DNS 模块 |
| 需要管理员 | 否 | 否 | **是** |

**全局模式不改捕获层**,只是路由规则变成"全部转发"——不认系统代理的程序照样直连。这是最常见的误解。

## 判定:现在到底是全局还是分流

### 方法一:看运行时路由(定位模式)

读 `binConfigs\config.json` 的 `routing.rules`,看兜底规则前有没有国内直连规则:

```powershell
$c = Get-Content "<v2rayN>\binConfigs\config.json" -Raw | ConvertFrom-Json
$i = 0; $c.routing.rules | ForEach-Object { $i++; "{0,2}. out={1,-7} port={2,-12} inTag={3,-14} ip={4} domain={5}" -f $i, $_.outboundTag, $_.port, ($_.inboundTag -join ','), (($_.ip -join ',') -replace '^(.{40}).*','$1...'), ($_.domain -join ',') }
```

- 有 `out=direct ip=[geoip:cn]` + `out=direct domain=[geosite:cn]` → 分流模式
- 只有 `out=proxy port=0-65535` 兜底、没有任何 cn 规则 → 全局模式

### 方法二:看 xray 的远端 IP 分布(最准,验证实际效果)

```powershell
$xid = (Get-Process xray).Id
Get-NetTCPConnection -OwningProcess $xid |
  Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0)' } |
  Group-Object RemoteAddress | Sort-Object Count -Descending |
  Select-Object Count, Name -First 15
```

- **只有代理服务器 IP** → 全局,所有流量都在隧道里
- **出现国内 IP**(与代理服务器 IP 并存) → 分流生效中

配合实测更清楚:访问几个国内站,再看远端 IP 是否新增国内地址。

```powershell
foreach ($u in @("https://www.baidu.com","https://www.qq.com","https://www.taobao.com")) {
  try { $null = Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 8 } catch {}
}
```

### 方法三:看配置索引

`guiNConfig.json` → `RoutingBasicItem.RoutingIndexId`:

- 为 `null` → 没有选中任何预设,v2rayN 只生成基础规则,**等价于全局**
- 为某个 Id → 对应 `guiNDB.db` 的 `RoutingItem` 表

## 切换路由预设(不改 GUI 的做法)

必须先**完全退出 v2rayN**,否则它退出时会把内存里的配置写回。

```python
import sqlite3, json

base = r"<v2rayN>\guiConfigs"
TARGET = "5741997081063016319"   # 从 RoutingItem 表里查到的目标预设 Id

with open(base + r"\guiNConfig.json", encoding="utf-8") as f:
    cfg = json.load(f)
cfg["RoutingBasicItem"]["RoutingIndexId"] = TARGET
with open(base + r"\guiNConfig.json", "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)

con = sqlite3.connect(base + r"\guiNDB.db")
cur = con.cursor()
cur.execute("UPDATE RoutingItem SET IsActive = 0")
cur.execute("UPDATE RoutingItem SET IsActive = 1 WHERE Id = ?", (TARGET,))
con.commit()
```

查预设清单:

```python
cur.execute("SELECT Id, Remarks, RuleNum, IsActive FROM RoutingItem ORDER BY Sort")
```

典型三条预设:`V4-绕过大陆(Whitelist)` / `V4-黑名单(Blacklist)` / `V4-全局(Global)`。

- **绕过大陆**:默认走代理,只有 `geoip:cn` / `geosite:cn` 直连。漏判只会让某个国内站变慢,不会打不开,容错最好。
- **黑名单**:默认直连,只有 gfw 列表走代理。新域名没收录就直连,可能打不开。

`guiNDB.db` 的 `RoutingItem.RuleSet` 是一个 JSON 字符串数组,字段:`Id / OutboundTag / Domain / Ip / Port / Network / Process / Enabled / Remarks`。

## 头号坑:DNS 查询全走代理 → 分流失效

**症状**:国内站比国外还慢。实测 baidu 2109ms,google 765ms。

**诊断三步**:

1. 查国内域名解析结果是不是海外 IP

```powershell
Resolve-DnsName www.baidu.com -Type A | Where-Object IPAddress | Select-Object Name, IPAddress
Resolve-DnsName www.bilibili.com -Server 119.29.29.29 -Type A | Where-Object IPAddress
```

百度的海外节点形如 `103.235.46.x`;B站的海外节点形如 `164.52.x.x`。国内正常应是 `110.242.x.x` / `39.156.x.x` 之类。

2. 反查归属确认

```powershell
Invoke-RestMethod "http://ip-api.com/json/<IP>?fields=country,city,isp"
```

3. **决定性验证**:在境外服务器上用同一个国内 DNS 查,结果一致 = 你的 DNS 查询就是从境外发出的

```bash
dig +short www.baidu.com @119.29.29.29
```

本地和服务器返回同一组 IP,说明本地解析走的不是国内网络。

**根因**:v2rayN 生成的运行时规则最后一条是

```json
{ "inboundTag": ["dns-module"], "outboundTag": "proxy" }
```

Xray 的 DNS 模块**所有查询都经代理发出**,包括发给国内 DNS(119.29.29.29)的查询。腾讯/阿里 DNS 按来源 IP 返回就近节点,于是国内域名被解析成海外 CDN → `geoip:cn` 匹配不上 → 又绕回代理。**分流规则存在,但被 DNS 化解了。**

注意:这条是 v2rayN **硬编码**的,不在 `RoutingItem.RuleSet` 里,加 IP 规则改不动它。

**已验证无效的思路**(别重复踩):

- 给 `119.29.29.29` 加 `/32` 路由指向物理网卡 → 无效,DNS 查询是 xray 内部路由进 proxy 出站,不走系统路由表
- 在 RuleSet 里加 `Ip: ["119.29.29.29"] → direct` → 无效,同一条查询先命中硬编码的 dns-module 规则

**可行方向**:

| 方案 | 做法 | 说明 |
|---|---|---|
| A. 换 sing-box 核心 | 设置 → 参数设置 → 核心类型,把 VLESS 对应项改为 sing-box | sing-box 的 DNS 可显式绑定 `outbound: direct`,根治 |
| B. 自定义 DNS + ECS | DNS 设置改用自定义 JSON,给国内 DNS server 加 `clientIP` | 不改出口,只纠正解析地理位置;依赖 DNS 服务端支持 EDNS |
| C. 接受 | — | 功能正常,仅延迟受损 |

**判定 DNS 是否修好**,就看一条:国内域名解析出的是不是国内 IP。

## TUN 连带影响清单

| 项 | 现状 | 影响 |
|---|---|---|
| `RouteExcludeAddress` | 默认 null,Docker 网段会自动排除(实测只排 `172.18.0.0/30`) | 新建的 compose 网络(172.19.x+)可能被 TUN 劫持,容器连不上时先查这条 |
| UDP 135/137-139/5353 | 被 block | 局域网投屏、共享打印机、NetBIOS 互传失效 |
| UDP 443 | 被 block(`XudpProxyUDP443: reject`) | QUIC/HTTP3 被拒,Google/ChatGPT 首屏多一个 RTT |
| MTU 9000 | xray TUN 默认 | 正常,xray 会按出站 MTU 重切,不用改 |
| `::/0 → TUN` | EnableIPv6Address=false 时的黑洞路由 | 物理网卡无公网 IPv6 时无影响,有 IPv6 的环境要注意 |

## 提权限制(AI 必须知道)

TUN 模式需要管理员权限。**AI 无法自动完成提权启动**:

- `Start-Process -Verb RunAs` 会弹 UAC,用户不点就无响应
- `Start-Process powershell ... -Verb RunAs` 被安全策略直接拦截(LOLBin 检测)

**结论**:改完配置后,恢复代理这一步必须交给用户手动完成(以管理员身份启动 v2rayN)。AI 只负责改配置 + 事后验证。

判定 TUN 是否真的生效:

```powershell
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, ifIndex
```

出现 `xray_tun` 才叫起来了;只有 WLAN 说明没提权或没点"启动"。
