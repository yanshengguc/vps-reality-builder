# 甲骨文 OCI 参考(待用户实测确认)

> 状态:CLI 部分已核实(2026-11-05);免费档实例创建与 xray 部署**尚未实测**,跑通后把本文件状态改为已确认。

## 免费档(2026 年现状,动手前先核实)

- Always Free 2026-06 已砍半:2 OCPU / 12GB ARM + 2 台 AMD 微型机(原 4 核 24GB)。
- 区域:新加坡首选(AI 用途 ChatGPT/Claude/Gemini/GitHub 均支持,延迟约 50–80ms);东京备选;美国没必要。
- 注册要绑卡验证(约 $1 预授权)+ 手机号。
- **新加坡 Ampere 免费实例经常没库存,要抢**;凤凰城相对好抢。抢不到别硬等,先换区试。

## CLI:有,叫 `oci`

```bash
pip install oci-cli
# 或官方安装脚本 / brew install oci-cli
```

认证两种方式(都由用户本人完成,Agent 不碰凭据):

1. **API 密钥(推荐,长期可用)**:`oci setup config` 交互向导生成密钥对,配置文件写 `~/.oci/config`,私钥 `~/.oci/oci_api_key.pem`(600 权限,这是凭据,别外传);然后用户自己去控制台 用户 → API Keys → Add API Key,粘贴公钥。没上传公钥前所有命令都会报授权错误。
2. **会话令牌(不用留长期密钥)**:`oci session authenticate`,浏览器登录一次,令牌默认 1 小时过期(可延长到 24h),用 `--auth security_token` 调用,过期用 `oci session refresh` 刷新。

OCI 控制台里的 Cloud Shell 自带已认证的 CLI,不用配。

## 建机(待实测,先占位)

- 镜像:Ubuntu 24.04;机型:Ampere A1(ARM,免费档)或 AMD 微型机。
- 安全组:OCI 叫 Security List / NSG,放行 22 与 443(入方向)。
- 部署:建机完成后按 SKILL.md ④ 部署 Reality,`scripts/deploy_reality.sh` 通用。
