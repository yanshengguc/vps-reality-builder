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

## 四、"IP 是不是被墙"判断

| 测试 | 被墙特征 |
|---|---|
| TCP 任意端口直连 | 全端口超时/重置 = IP 进墙;仅 443 不通 = 端口级封锁,换端口 |
| ping | 不完全可靠(ICMP 被弃用很常见),仅参考 |
| 境外回连(经用户现有代理) | 境外通境内不通 = 进墙 |
| 解决 | Azure/GCP 删机换 IP 重建(几分钟);裸 VPS 找商家换 IP |

## 五、Windows 本机环境坑(影响本 skill 的执行)

- **浏览器自动化不可用**:拉起的浏览器(Edge CDP/agent-browser --headed)窗口不显示,渲染正常但用户看不见 → 云门户操作全走 CLI + 设备码,不要尝试"接管浏览器"
- **bash 调 .cmd/.bat**:用 PowerShell 或全路径 `az.bat`;PowerShell 工具不回显 stdout,重要输出 `Set-Content` 写文件再 Read
- **嵌套引号地狱**:SSH 远程跑复杂命令用 `ssh ... 'bash -s' < script.sh`,不写一整行内联命令
- **沙箱**:写 `~/.azure`、`~/.ssh` 等目录可能被拒,需要用户批准升级或改用工作区目录(CLOUDSDK_CONFIG / AZURE_CONFIG_DIR)
- qrcode 库装隔离 venv:`<managed-python-env>\Scripts\pip.exe install qrcode`,不要污染全局

## 六、 Reality 伪装站(SNI)选择

要求:TLS1.3 + h2(用 `openssl s_client -connect <d> -alpn h2` 现场验证)、大站高信誉、**与服务器地理/品牌合理**(首尔配 samsung.com 是范例;日本可配 www.sony.com 等;避免用 microsoft.com 之类"谁都可能用"的——不是不行,是"服务器在首尔却伪装东京站"不自然)。serverNames 与 dest 必须一致。
