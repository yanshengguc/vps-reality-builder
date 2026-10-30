# 故障排查手册(按命中率排序)

## 一、"443 连不通"三层诊断(2026-09 实战:坑在第三层)

症状:服务器上 `ss -tlnp` 显示 443 在监听,本地却 TCP 超时。**按顺序查,上一层通过才查下一层**:

1. **云安全组**:
   - Azure:`az network nsg rule list` 核对入站规则(看 priority/port/direction);规则即时生效
   - GCP:`gcloud compute firewall-rules list`,确认规则 target-tags 和实例 tags 匹配
2. **系统内 ufw**(本次实战的真凶):`sudo ufw status verbose`。Ubuntu 云镜像经常 active + default deny,只放行了 22 和旧端口。`sudo ufw allow 443/tcp` 秒解决。
   - 同理检查 iptables:`sudo iptables -L INPUT -n | head`
3. **网络路径/GFW**:以上都通仍超时 → 可能该 IP 的 443 被墙或路径丢包。
   - 交叉验证:让用户开着自己的旧代理,从境外回连测 `curl --resolve <sni>:443:<ip>`;境外通、境内不通 = 进墙/路径问题 → 换端口(8443 等)或换 IP

**诊断时不要在服务器上测 443**——127.0.0.1 测试绕过 ufw,会得出"一切正常"的假结论。必须从本地/外部测。

## 二、x25519 密钥解析(踩过的坑)

Xray 26.x 输出格式:

```
PrivateKey: Xx1a2B3c...(示例占位,非真实值)
Password (PublicKey): Yy4d5E6f...(示例占位,非真实值)
Hash32: Zz7g8H9i...(示例占位,非真实值)
```

旧格式是 `Private key: xxx` / `Public key: xxx`。兼容解析:

```bash
PRIV=$(echo "$PAIR" | grep -iE 'private' | head -1 | awk -F': *' '{print $2}')
PUB=$(echo "$PAIR"  | grep -iE 'public|password' | head -1 | awk -F': *' '{print $2}')
[ -z "$PRIV" ] && echo "解析失败,中止" && exit 1   # 空私钥 = 配置校验失败 = 服务中断
```

**事故链回放**(引以为戒):空私钥写进 config → `-test` 失败但脚本仍 restart → xray 起不来 → 用户现有节点中断。所以:① 先 `-test` 再 restart;② restart 失败立即 `cp config.json.bak.* config.json && systemctl restart xray` 回滚;③ 解析结果先验长度再入库。

## 三、设备码登录

- 设备码 15 分钟过期;用户中途卡住(如"代码无法工作")大概率是过期,重发即可
- 提醒用户话术:"输完码要一直走到显示已登录,别只输码就关页面"
- 沙箱环境写 `~/.azure`/`~/.config/gcloud` 可能被拒 → AZURE_CONFIG_DIR / CLOUDSDK_CONFIG 指到工作区

## 四、"IP 是不是被墙"判断(2026-10 实战升级版)

**核心思路:先证明服务器活着,再证明只有国内方向不通。**

### ① 最快定性:境外回连(check-host)

```bash
# 提交检测(无需 key)
R=$(curl -s --max-time 20 -H "Accept: application/json" \
  "https://check-host.net/check-tcp?host=<IP>:443&max_nodes=4")
ID=$(echo "$R" | python -c "import sys,json;print(json.load(sys.stdin)['request_id'])")
sleep 12
curl -s -H "Accept: application/json" "https://check-host.net/check-result/$ID"
```

- 返回形如 `{"de2.node...":[{"address":"<IP>","time":0.23}]}` = **境外能连,服务器活着**
- 同时本地全端口超时 → **IP 被墙**
- 返回 `null` 或空 = 该节点也连不上,服务器可能真挂了(结合云控制台确认)

### ② 端口矩阵:区分封锁层级

```python
for p in [80,443,22,10086,3389,8080,1234]:
    # 记录 OPEN / Timeout / ConnectionRefused
```

| 现象 | 含义 |
|---|---|
| **所有端口 Timeout(连 RST 都没有)** | **IP 级黑名单**,GFW 静默丢包 |
| 部分端口 ConnectionRefused | 网络通,只是服务没监听 |
| 只有某个端口不通 | 端口级封锁,换端口即可 |

⚠️ **25 端口永远显示 OPEN**——国内运营商对 SMTP 端口的伪响应劫持,连谁都是"通的",绝不能当连通证据(2026-10 实战踩过)。

### ③ 路由佐证

`tracert -d <IP>`:若能看到云厂商骨干跳点(如 Azure 的 `51.10.x.x`,~100ms)却到不了目标端口 → 拦截点在云入口之前,是**定向丢包**,而不是运营商出口拥堵。

### ④ 处置

换 IP(命令见 [azure.md](azure.md) 的"更换公网 IP"章节)。换完第一件事:**移除同机的明文 inbound**,否则新 IP 会被同样方式再次封禁。

## 五、Windows 本机环境坑(影响本 skill 的执行)

- **浏览器自动化不可用**:拉起的浏览器(Edge CDP/agent-browser --headed)窗口不显示,渲染正常但用户看不见 → 云门户操作全走 CLI + 设备码,不要尝试"接管浏览器"
- **bash 调 .cmd/.bat**:用 PowerShell 或全路径 `az.bat`;PowerShell 工具不回显 stdout,重要输出 `Set-Content` 写文件再 Read
- **嵌套引号地狱**:SSH 远程跑复杂命令用 `ssh ... 'bash -s' < script.sh`,不写一整行内联命令
- **沙箱**:写 `~/.azure`、`~/.ssh` 等目录可能被拒,需要用户批准升级或改用工作区目录(CLOUDSDK_CONFIG / AZURE_CONFIG_DIR)
- qrcode 库装隔离 venv:`<managed-python-env>\Scripts\pip.exe install qrcode`,不要污染全局

## 六、"节点卡/慢"诊断顺序(2026-09-24 实战,根因出人意料)

症状:延迟看着还行,但网页/视频卡。**不要一上来就怀疑服务器或换机**,按顺序四步:

### 第 1 步:先确认客户端"实际在用哪个节点"(最容易踩空)

v2rayN 的节点库是 sqlite:`v2rayN 安装目录/guiConfigs/guiNDB.db`。**先复制一份再读**(原库被 GUI 占用):

```python
import sqlite3, shutil
shutil.copy(guiNDB_path, workspace_copy)
cur.execute('select Remarks,Address,Port,ConfigType,Network,StreamSecurity,Sni,Flow from ProfileItem')
```

`ConfigType`:1=VMess,5=VLESS。另看 `ServerStatItem` 的 TotalDown/TodayDown 判断哪个在用。

### 第 2 步:本地测链路质量(区分"物理远"和"被干扰")

```python
# TCP 握手 20 次:看 min/avg/max/标准差/失败数
```

判读:RTT 与地理位置匹配且抖动小(<20ms)、零失败 → **物理链路没问题**,卡一定在协议/服务器/客户端配置层。本次首尔机 121ms、抖动 9ms、0/20 失败,链路是好的。

### 第 3 步:服务器侧体检(SSH)

```bash
uptime; nproc; free -m; ps -eo pcpu,pmem,comm --sort=-pcpu | head -8
systemctl is-active xray; ss -tlnp | grep -E ':(443|10086)'
# VM 规格(不用 az 登录就能拿到):
curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['vmSize'],d['location'])"
# 出口带宽
curl -s -o /dev/null -w "%{speed_download} B/s\n" --max-time 40 https://speed.cloudflare.com/__down?bytes=10000000
```

**B 系列突发实例(Standard_B1s/B2ats_v2 等)要警惕 CPU 积分耗尽被节流**——持续跑代理会掉速。积分余量只能在云门户看(VM → 指标 → CPU Credits Remaining),CLI 看不到。

### 第 4 步(本次真正的根因):对比"服务器已部署" vs "客户端在用"

```bash
# 服务器已有哪些 inbound
python3 -c "import json;c=json.load(open('/usr/local/etc/xray/config.json'));[print(i['port'],i['protocol']) for i in c['inbounds']]"
# 本地验证 443 是不是 Reality(看到伪装站真实证书 + TLS1.3 即成立)
echo | openssl s_client -connect <IP>:443 2>/dev/null | grep -E 'subject=|Protocol'
```

**高频事故:服务器上 Reality 443 早就部署好了,但客户端还在用旧的明文 VMess(非标准端口、无 TLS)。**明文 VMess 的头部特征极易被识别并 QoS,症状正是"延迟不高但卡"。→ 解法不是换机,是把 Reality 节点导入客户端并用它。参数从工作区 `vless-node-info.md` 取(别重新生成密钥,旧 inbound 的 UUID/pbk/sid 不变)。

### 延伸:"下午/晚上卡、半夜就好了"——时段性跨境丢包(2026-09-24 实战)

先**排除服务器**,三条硬证据(都 SSH 上跑):

```bash
vmstat 1 3          # 最后一列 st = CPU steal,>0 才是被虚拟化节流(B 系列积分耗尽会体现)
sar -u -f /var/log/sysstat/sa$(date +%d) | tail   # 历史 CPU,卡的那段是否真忙
ping -c 5 -W 2 223.5.5.5      # 反向:服务器→国内。0% 丢包而本地→服务器有尖峰 = 出境/入境不对称
```

判定:服务器 idle 高、st=0、反向 ping 无丢包、出口带宽正常 → **服务器无辜,丢包在国内侧出境段(运营商国际出口晚高峰拥塞)**。特征:基线正常(如 120ms)叠加偶发 +1000ms 尖峰(SYN 丢包后 1s 重传),TCP 在 5% 丢包下吞吐掉一半。

**这类卡顿换节点、换 Reality 都治不好**——Reality 解决的是"被识别",不是"丢包"。真正的修复是**抗丢包协议**:在现有机器上加 Hysteria2 或 TUIC inbound(QUIC/UDP,同等丢包下吞吐远高于 TCP,Hysteria2 还能开 FEC、端口跳跃)。Reality 保留做日常,高峰切 Hysteria2。注意少数运营商对 UDP 有 QoS,需实测确认。

### 相关:v2rayN 当前是否在运行

本地 10808/10809 端口全 closed = v2rayN 没启动,此时**无法实测吞吐**,只能做静态 + 外部探测诊断。要测真实速度必须让用户先启动 v2rayN 并选定节点。

## 七、Hysteria2 客户端连不上:v2rayN 新版安全策略(2026-10-29 实战)

**症状**:服务端 `systemctl is-active` = active、UDP 端口在监听、tcpdump 能看到客户端的 UDP 包到达,但客户端就是连不上;服务端日志**没有任何连接记录**(因为 QUIC 握手在认证层之前就被客户端放弃了)。

先看**客户端日志**(v2rayN:`guiLogs/YYYY-MM-DD.txt`),典型报错:

```
检测到不安全配置:AllowInsecure 已启用,但未提供证书。这可能会导致中间人攻击。
当前节点使用未加密连接... 此类节点无法通过 26.2.6+ 版本的 Xray 核心连接
```

**根因**:自签证书 + `insecure=1` 的组合,在 v2rayN V7.25.4 / Xray 26.2.6+ 之后被安全策略直接拒绝(防 MITM)。**与网络、防火墙、服务端配置完全无关**——别再往端口和 NAT 方向查了。

### 解法一(推荐):补证书公钥指纹 pinSHA256

```bash
# 服务器上算指纹(注意是证书公钥的 SHA256,不是证书文件本身的)
sudo openssl x509 -in /etc/hysteria/cert.pem -pubkey -noout \
  | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
```

把结果 **URL 编码**(`+`→`%2B`、`/`→`%2F`、`=`→`%3D`)后拼进链接:

```
hysteria2://<pw>@<IP>:443/?sni=<sni>&insecure=1&pinSHA256=<encoded>#<name>
```

### 解法二:v2rayN 换 sing-box 核心

设置 → 核心类型 → 把 Hysteria2 对应的核心改为 sing-box(sing-box 不强制校验证书)。

### 解法三:真实证书

用域名 + ACME 申请 Let's Encrypt,彻底摆脱 `insecure`,顺带提升伪装度。

**部署时的预防**:自签证书方案应在部署当时就把 pinSHA256 一起算出来写进节点文档,别等客户端报错才发现。

## 八、 Reality 伪装站(SNI)选择

要求:TLS1.3 + h2(用 `openssl s_client -connect <d> -alpn h2` 现场验证)、大站高信誉、**与服务器地理/品牌合理**(首尔配 samsung.com 是范例;日本可配 www.sony.com 等;避免用 microsoft.com 之类"谁都可能用"的——不是不行,是"服务器在首尔却伪装东京站"不自然)。serverNames 与 dest 必须一致。
