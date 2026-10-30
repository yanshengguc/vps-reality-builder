# Azure 实战手册(全部命令经 2026-09 实测)

## az wrapper(必建)

bash 里 `az` 有路径空格 + 沙箱双重问题,统一用 wrapper:

```bash
#!/bin/bash
# <workspace>/.workbuddy/azw.sh
export AZURE_CONFIG_DIR="<workspace>\\.workbuddy\\azconfig"
exec "/c/Program Files/Microsoft SDKs/Azure/CLI2/Scripts/az.bat" "$@"
```

要点:
- `AZURE_CONFIG_DIR` 指向工作区目录,绕开 bash 沙箱写 `~/.azure` 被拒的坑(症状:`FileNotFoundError: ...\.azure\commands\...log`,目录明明存在——沙箱虚拟化导致)。
- winget 装的 CLI 实际可执行文件是 `az.bat`(`Scripts/` 下),新 shell 才会刷新 PATH;沙箱里 PATH 不刷新,直接用全路径。
- 若 `az.bat` 输出为空,兜底直接调内置 python:`"C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe" -m azure.cli ...`(同样带 AZURE_CONFIG_DIR)。

## 登录(设备码)

```bash
$AZW login --use-device-code --output json > az_login.json 2> az_login_err.txt   # 后台跑
cat az_login_err.txt   # 里面是 "To sign in, use a web browser ... enter the code XXXX"
```

- 设备码 **15 分钟过期**,过期重发;用户需"输完码走到显示已登录"。
- 登录结果在 az_login.json,核对 `name`/`state`(如 Azure for Students / Enabled)。

## 区域白名单(Azure for Students 的天坑)

学生订阅被 Microsoft 系统策略 `sys.regionrestriction` 限制,**用户改不了**。2026-09 实测白名单:`southeastasia, koreacentral, indonesiacentral, malaysiawest, japaneast`(美国全封)。

```bash
# 查询当前白名单
$AZW policy assignment list --disable-scope-strict-match --output json
# 找 name=sys.regionrestriction 的 assignment,读 parameters.listOfAllowedLocations.value
```

- **假象警告**:资源组(resource group)在任何区域都能建成功(策略不拦 RG),但 VM/VNET/NSG/IP 会被 `RequestDisallowedByAzure` 拒。别被 RG 建成功误导。
- 需要美国:换 GCP/DO,或用户提工单/新开 PAYG 订阅。

## 建 VM(实测命令模板)

```bash
$AZW group create -n rg-vless-<region> -l <region> --output none
PUBKEY=$(cat ~/.ssh/id_ed25519_<cloud>.pub)
$AZW vm create -n <vm-name> -g rg-vless-<region> -l <region> \
  --image Canonical:ubuntu-24_04-lts:server:latest \
  --size Standard_B1s \
  --admin-username azureuser \
  --ssh-key-value "$PUBKEY" \
  --public-ip-sku Standard \
  --storage-sku Standard_LRS \
  --os-disk-size-gb 30 --output json
# 确认结果(vm create 输出可能解析失败,单独查)
$AZW vm list -g rg-vless-<region> -d --query "[].{name:name,state:powerState,ip:publicIps}" --output json
```

B1s 规格:1C1G,跑 Xray 绰绰有余,约 $4-5/月。学生订阅注意额度。

## 开端口(NSG)+ 开机进入

```bash
$AZW network nsg rule create -g <rg> --nsg-name <nsg-name> -n reality443 \
  --priority 320 --direction Inbound --access Allow --protocol Tcp \
  --destination-port-range 443 --output none
$AZW network nsg rule list -g <rg> --nsg-name <nsg-name> --query "[].{name:name,pri:priority,port:destinationPortRange}" --output tsv
```

## 已有 VM 的接 管(用户忘了密码/密钥时)

```bash
# VMAccess 扩展追加公钥到现有管理员(先查真实用户名!)
$AZW vm show -g <rg> -n <vm> --query osProfile.adminUsername --output tsv
$AZW vm user update -g <rg> -n <vm> --username <admin> --ssh-key-value "$PUBKEY" --output none
```

追加后正常 `ssh -i <key> <admin>@<ip>`。这是"追加"不是重置,原密钥/密码不受影响。

## 更换公网 IP(IP 被墙时的标准操作,2026-10 实测)

**服务端零改动**:xray / hysteria 都监听 `0.0.0.0`,NSG 与 ufw 绑在 NIC / 子网上,换 IP 只影响客户端要填的地址。

```bash
# 1. 摸现状(资源名不要猜)
$AZW vm list -d -o table
$AZW network public-ip list -o table
$AZW network nic ip-config list -g <rg> --nic-name <nic> -o table     # 通常叫 ipconfig1

# 2. 新建静态 IP(必须同区域;学生订阅注意区域白名单)
$AZW network public-ip create -g <rg> -n <rg>-ip2 \
  --sku Standard --allocation-method Static --location <region> \
  --query "publicIp.ipAddress" -o tsv

# 3. 换绑到网卡的 IP 配置
$AZW network nic ip-config update -g <rg> --nic-name <nic> -n ipconfig1 \
  --public-ip-address <rg>-ip2

# 4. 确认生效
$AZW vm list -d -o table        # PublicIps 应显示新地址

# 5. 释放旧 IP(不释放会继续按小时计费)
$AZW network public-ip delete -g <rg> -n <旧ip资源名>
```

要点:
- 换绑瞬间公网地址切换,但 **xray/hysteria 进程不重启**,已建立的连接会断,客户端重连即可
- **旧 IP 删除不可逆**:等新 IP 能 SSH 登录、443 握手正常后再删
- 换完立刻做两件事:①移除同机明文 inbound ②更新客户端地址并实测
- 验证新 IP 是否也被封:再跑一遍 check-host/端口矩阵,不要假设"新的就一定能用"

## 清理

```bash
$AZW resource list -g <rg> --output tsv        # 确认组内无重要资源
$AZW group delete -n <rg> -y --no-wait --output none
```

删组前必须让用户确认;先 `resource list` 展示组里有什么。
