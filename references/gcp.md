# GCP 实战手册(美国节点首选,待首跑后回填实测细节)

GCP **没有区域白名单**,免费试用 $300/90 天无需学生认证,绑卡即可。给用户要美国 IP 时首选。

## 安装与登录

```bash
winget install --id Google.CloudSDK --silent --accept-package-agreements --accept-source-agreements
# 新 shell 刷新 PATH 后,或用全路径 <SDK>\google-cloud-sdk\bin\gcloud
gcloud auth login --no-launch-browser    # 输出 URL,用户在自己浏览器完成登录
gcloud config set project <project-id>   # 试用开通时会自动建一个项目
```

注意:开通试用($300)那一步——注册、绑卡、同意条款——必须用户本人在浏览器完成,AI 只负责之后的 CLI 操作。

## 建 VM(美国,免费层规格)

```bash
gcloud compute instances create vless-us1 \
  --zone=us-west1-b \
  --machine-type=e2-micro \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --network-tier=STANDARD
gcloud compute instances list   # 拿 EXTERNAL_IP
```

- e2-micro:2 共享 vCPU/1GB,跑 Xray 足够;us-west1/us-central1/us-east1 各有 1 台永久免费层额度(试用到期后 e2-micro 可进免费层)。
- 先选 us-west1(对国内相对好);开机后测国内连通性,IP 不通就删机换 zone 重建(换 IP 零成本,几分钟的事)。

## 防火墙(GCP 是"防火墙规则"挂 VPC 上,不是挂 VM)

```bash
gcloud compute firewall-rules create allow-reality-443 \
  --direction=INGRESS --action=ALLOW --rules=tcp:443 \
  --source-ranges=0.0.0.0/0 --target-tags=vless-node
# 建 VM 时带 --tags=vless-node;或用 network tags 关联
```

**别忘了系统内 ufw**——Ubuntu 镜像默认 ufw 是 inactive,但按 troubleshooting 的诊断顺序检查一遍再下结论。

## 计费提醒(给用户的预期管理)

- $300/90 天:e2-micro 约 $7/月,额度覆盖绰绰有余
- **出站流量超额 $0.12/GB**,从额度里扣;看视频多要有心理预期
- 免费层含 1GB/月出站(北美出口),代理用途主要靠额度消化
- 试用期不自动扣款,到期需手动升级付费账号;提醒用户设预算告警(billing → budget)

## 与 Azure 的差异速记

- GCP 防火墙规则挂 VPC/标签,不挂实例;改动即时生效
- SSH 密钥:`gcloud compute os-login` 或把公钥加进 project metadata;最简单是建实例时 `--metadata=ssh-keys="user:<pubkey>"`
- 静态 IP:默认 ephemeral,固定要 `gcloud compute addresses create`(试用内免费保留中的静态 IP)
