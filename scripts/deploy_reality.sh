#!/bin/bash
# deploy_reality.sh — 在已有 xray 的 Ubuntu VPS 上合并部署 VLESS Reality 443 inbound
# 用法: ssh -i <key> <user>@<ip> 'bash -s' < deploy_reality.sh
# 可选环境变量: SNI(默认 www.samsung.com) REALITY_PORT(默认 443)
# 行为: 备份现有 config -> 合并新 inbound(保留旧配置) -> -test 校验 -> restart -> 验证
# 失败自动回滚,保证现有节点不中断
set -u

XRAY=/usr/local/bin/xray
XRAY_DIR=/usr/local/etc/xray
CONF=$XRAY_DIR/config.json
SNI="${SNI:-www.samsung.com}"
PORT="${REALITY_PORT:-443}"

echo "=== 0. 前置检查 ==="
[ -x "$XRAY" ] || { echo "ERROR: $XRAY 不存在,请先安装 xray(官方安装脚本)"; exit 1; }
sudo systemctl is-active --quiet xray && WAS_ACTIVE=1 || WAS_ACTIVE=0
echo "xray 版本: $($XRAY version | head -1)"
echo "SNI=$SNI PORT=$PORT"

echo "=== 1. SNI 候选验证(需 TLS1.3 + h2) ==="
tls=$(echo | timeout 6 openssl s_client -connect "$SNI:443" -servername "$SNI" 2>/dev/null | grep -o 'TLSv1.3' | head -1)
alpn=$(echo | timeout 6 openssl s_client -connect "$SNI:443" -alpn h2 2>/dev/null | grep 'ALPN protocol' | awk '{print $3}')
[ "$tls" = "TLSv1.3" ] && [ "$alpn" = "h2" ] || { echo "ERROR: $SNI 不满足 TLS1.3/h2,换一个伪装站"; exit 1; }
echo "SNI 验证通过"

echo "=== 2. 备份现有配置 ==="
BAK="${CONF}.bak.$(date +%Y%m%d%H%M%S)"
sudo cp "$CONF" "$BAK"
echo "备份: $BAK"

echo "=== 3. 生成凭据 ==="
UUID=$(cat /proc/sys/kernel/random/uuid)
PAIR=$(sudo $XRAY x25519)
PRIV=$(echo "$PAIR" | grep -iE 'private' | head -1 | awk -F': *' '{print $2}')
PUB=$(echo "$PAIR" | grep -iE 'public|password' | head -1 | awk -F': *' '{print $2}')
SID=$(openssl rand -hex 8)
[ -z "$PRIV" ] || [ -z "$PUB" ] && { echo "ERROR: x25519 解析失败,中止(参考 troubleshooting 二)"; exit 1; }
echo "密钥长度校验: PRIV=${#PRIV} PUB=${#PUB}"

echo "=== 4. 合并 inbound(保留现有配置) ==="
sudo python3 - "$UUID" "$PRIV" "$SID" "$SNI" "$PORT" <<'PYEOF'
import json, sys
uuid, priv, sid, sni, port = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
path = '/usr/local/etc/xray/config.json'
c = json.load(open(path))
ports = [i.get('port') for i in c.get('inbounds', [])]
if port in ports:
    print(f"PORT {port} 已存在 inbound,跳过合并(如需重建请先手动清理)")
    sys.exit(2)
c['inbounds'].append({
    "listen": "0.0.0.0", "port": port, "protocol": "vless",
    "settings": {"clients": [{"id": uuid, "flow": "xtls-rprx-vision"}], "decryption": "none"},
    "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {"show": False, "dest": f"{sni}:443", "xver": 0,
                            "serverNames": [sni], "privateKey": priv, "shortIds": [sid]}
    },
    "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}
})
json.dump(c, open(path, 'w'), indent=2)
print("合并完成, 当前 inbounds:", [i.get('port') for i in c['inbounds']])
PYEOF
[ $? -eq 0 ] || { echo "合并中止,配置未改动"; exit 1; }

echo "=== 5. 校验配置 ==="
if ! sudo $XRAY -test -config "$CONF" >/dev/null 2>&1; then
    echo "ERROR: 配置校验失败,回滚!"
    sudo cp "$BAK" "$CONF"
    sudo systemctl restart xray
    echo "已回滚到备份并重启,当前状态: $(systemctl is-active xray)"
    exit 1
fi
echo "Configuration OK"

echo "=== 6. 重启并验证 ==="
sudo systemctl restart xray
sleep 2
STATE=$(systemctl is-active xray)
echo "xray 状态: $STATE"
if [ "$STATE" != "active" ]; then
    echo "ERROR: 服务未起来,回滚!"
    sudo cp "$BAK" "$CONF"; sudo systemctl restart xray; sleep 2
    echo "回滚完成,当前状态: $(systemctl is-active xray)"
    exit 1
fi
sudo ss -tlnp | grep -E ":(443|$PORT)\b"

echo "=== 7. 本机伪装验证(注意:这只是回环测试,外部可达性须从本地另行验证) ==="
echo | timeout 6 openssl s_client -connect 127.0.0.1:$PORT -servername "$SNI" 2>/dev/null | grep -E 'subject=|TLSv1.3' | head -3

echo "===CREDENTIALS==="
echo "UUID=$UUID"
echo "PUBKEY=$PUB"
echo "SHORTID=$SID"
echo "SNI=$SNI"
echo "PORT=$PORT"
echo "BACKUP=$BAK"
# 注意:以上凭据由调用方写入用户本地节点信息文件,不得写入任何日志/仓库/记忆
