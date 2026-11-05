# Cloady 容器部署(VLESS + WS + TLS,免费档)

Cloady(NeptoLab,2026-10-27 上线,public beta)是容器应用平台,不是 VPS:没有 root、没有 SSH 直连,部署靠上传文件夹或接 GitHub 仓库,平台自动给 HTTPS。适合"不要钱、能跑起来就行"的节点;代价是经过平台边缘转发,延迟比 VPS 直连高,且免费档只有 0.5 vCPU。

## 免费档(部署前先在 Billing 页核实)

- workspace 内应用合计不超过 0.5 vCPU / 1 GB 内存 / 5 GB 磁盘即 $0/月,不绑卡。
- 免费档含每月 15 GB 出站流量(官网文档 2026-11-05 版;早期版本写 100 GB,以 Billing 页为准)。
- 免费档只适用于账号下第一个有应用且仍在额度内的 workspace;超出额度或免费档被占用时部署报 `payment_required`。
- 2026-11-05 实测:usw1(美西)标注为 FREE TIER,永久免费,非一个月试用。官网文档与论坛说法冲突时以 Billing 页和部署时的实际报错为准;若只剩试用,按用户要求停手,不部署。

## 注册

- 邮箱验证码登录。验证码由用户在聊天里提供,AI 不碰密码,MFA 同理。
- 登录页有 Cloudflare Turnstile 人机验证,个别浏览器环境会被连续拒绝;换环境重试即可,不要反复硬点。
- 本技能铁律 1(绝不用浏览器自动化操作云门户)的例外只适用于这种情形:登录凭据完全由用户提供、且平台没有可用的 CLI 登录方式。Cloady 有 CLI 与 MCP,能走 CLI 时优先 CLI。

## 部署文件(三个文件放同一文件夹根目录)

`Dockerfile`(官方 xray 镜像没有 shell,必须多阶段构建把二进制拷进 Alpine):

```dockerfile
FROM teddysun/xray:latest AS builder
FROM alpine:latest
RUN apk add --no-cache ca-certificates
COPY --from=builder /usr/bin/xray /usr/bin/xray
COPY config.json /etc/xray/config.json
EXPOSE 3000
CMD ["/usr/bin/xray", "run", "-c", "/etc/xray/config.json"]
```

`config.json`(VLESS + WS,容器内监听 3000,不配 TLS,平台边缘统一终结 TLS):

```json
{"inbounds":[{"port":3000,"protocol":"vless","settings":{"clients":[{"flow":"","id":"<UUID>"}],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/<随机路径>"}}}],"log":{"loglevel":"warning"},"outbounds":[{"protocol":"freedom"}]}
```

`docker-compose.yml`(端口对外发布为 Web 端口,资源限制卡进免费档):

```yaml
services:
  xray:
    build: .
    ports:
      - "3000:3000"
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
```

三个文件可用 `scripts/gen_cloady_ws.sh <目标目录>` 一键生成(UUID 与 WS 路径随机生成,不回显到终端)。

## 部署步骤

1. 新建 workspace,新建应用(名如 `xray`),区域选 usw1(美西),环境 production。
2. 文件夹上传方式部署上述三个文件。平台按根目录的 compose 文件识别为 compose 部署,服务名取自 compose。
3. 服务端口 3000 对外发布为 Web 端口,平台自动签发通配符 TLS 证书,对外走 443,域名形如 `<应用名>-<随机码>-<workspace>.cloady.io`。
4. 无 compose 文件时,平台默认服务端口为 3000(可用 `PORT` 变量改);有 compose 文件时以 `ports:` 为准。

## 端到端验证(部署完必做,不要只看 RUNNING)

```bash
# 1. 域名可解析
getent hosts <域名>
# 2. WS 路径返回 400 = xray 在线(xray 对非 WS 请求的正常响应);根路径 404 也正常
curl -s -o /dev/null -w "%{http_code}\n" "https://<域名>/<WS路径>"
```

- 平台偶有 DNS 维护公告,新域名可能暂时无法访问;先确认证书状态为 ISSUED、服务 RUNNING,再换网络重试,不要立刻判定部署失败。
- 客户端实连验证:把生成的 `vless://` 链接导入 v2rayNG(剪贴板导入),选为活动节点后访问外网。TLS 对时间敏感,手机系统时间偏差大时会握手失败,先核对时间。

## 客户端链接格式

```
vless://<UUID>@<域名>:443?encryption=none&security=tls&sni=<域名>&type=ws&host=<域名>&path=%2F<WS路径>#<备注>
```

## 与 VPS Reality 路径的取舍

| 维度 | Cloady WS+TLS | VPS Reality |
|---|---|---|
| 费用 | $0 永久免费档 | 按云厂商免费层/学生额度,到期要续 |
| 延迟 | 经平台边缘转发,比直连高 | 直连最低 |
| 抗封 | 对外是平台域名/IP,源站不暴露 | IP 被墙需换 IP(见 SKILL.md 运维节) |
| 运维 | 无 SSH,改配置靠重新部署 | SSH 直连,改配置灵活 |

已被墙过一次、追求最低延迟时选 VPS Reality;只要"能用、免费、快速上线"时选 Cloady。两者不要混在同一台机器上比较,铁律 4 的明文 inbound 风险同样适用:不要在同一服务里再加 VMess/SS 明文 inbound。
