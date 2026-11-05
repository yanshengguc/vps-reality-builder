# AWS 参考

## 免费额度(2026 年现状,先核对再动手)

AWS 免费档在 2025 年改过规则,**新老账号不一样**,别按过期攻略写配置:

- **2025-07-15 之后注册的新账号**:$200 额度,6 个月内用完,EC2 用量从额度里扣,没有单独的 750 小时免费。$200 花完或 6 个月到期即按量计费。
- **2025-07-15 之前注册的老账号**:经典 12 个月免费档仍在,EC2 每月 750 小时 t2.micro 或 t3.micro(够一台 24/7 跑),30GB EBS,每月 15GB 出站流量,12 个月后按量计费。

动手前先去 Billing 控制台 Free Tier 使用量页面核实自己账号是哪一档。**务必设账单告警**(Billing → Budgets,设 $1 或 $5 告警),额度用完不会自动停机,只会开始计费。

## 登录(用户本人操作,Agent 不碰凭据)

- SSO 登录:`aws configure sso`,按提示在浏览器里完成认证。
- Access Key 登录:`aws configure`,填 Access Key ID / Secret / 区域。密钥由用户自己在 IAM 控制台生成,不要发给 Agent,不要写进仓库。

## 建机

- 镜像:Ubuntu 24.04 LTS(官方 AMI,按区域搜 `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*`)。
- 机型:t2.micro 或 t3.micro(1 vCPU / 1GB,免费档覆盖的型号;开别的型号直接计费)。
- 密钥对:新建专用密钥对(如 `id_ed25519_aws`),`.pem` 文件 `chmod 400`,丢了就登不上,别删。
- 安全组(建机时新建独立安全组,只放行需要的端口):

```bash
# 放行 SSH(部署用)和 443(Reality 用)
aws ec2 authorize-security-group-ingress --group-id <sg-id> --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id <sg-id> --protocol tcp --port 443 --cidr 0.0.0.0/0
```

防火墙同样是两层:安全组 + 系统内 ufw,两层都要放行,诊断顺序见 [troubleshooting.md](troubleshooting.md)。

## 区域

无系统级白名单,美国区可用。选区原则:离用户近的优先(延迟低);要美国 IP 直接选 us-east-1 / us-west-2 等美国区。

## 部署

建机完成后按 SKILL.md ④ 部署 Reality,`scripts/deploy_reality.sh` 通用。**AWS 已确认跑通**(2026-11-05 用户确认)。

## 关机/删机(防扣费)

- 不用时停机:`aws ec2 stop-instances --instance-ids <id>`,停机后 EBS 磁盘仍计费(30GB 内免费档覆盖)。
- 彻底不要:终止实例 + 删除安全组 + 释放弹性 IP(弹性 IP 挂在已删实例上会一直计费),再去 Billing 确认无未结费用。
