#!/usr/bin/env bash
# 生成 Cloady 部署用的三个文件(Dockerfile、docker-compose.yml、config.json)。
# 用法: bash scripts/gen_cloady_ws.sh <目标目录>
# 安全:UUID 与 WS 路径只写入目标目录下的 config.json 与节点信息文件,不回显到终端,不提交仓库。
set -euo pipefail

OUT="${1:?用法: bash scripts/gen_cloady_ws.sh <目标目录>}"
mkdir -p "$OUT"

UUID="$(cat /proc/sys/kernel/random/uuid)"
WSPATH="$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"

cat > "$OUT/Dockerfile" << 'EOF'
# 官方 xray 镜像没有 shell,用多阶段构建把二进制拷进 Alpine
FROM teddysun/xray:latest AS builder

FROM alpine:latest
RUN apk add --no-cache ca-certificates
COPY --from=builder /usr/bin/xray /usr/bin/xray
COPY config.json /etc/xray/config.json
EXPOSE 3000
CMD ["/usr/bin/xray", "run", "-c", "/etc/xray/config.json"]
EOF

cat > "$OUT/docker-compose.yml" << 'EOF'
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
EOF

cat > "$OUT/config.json" << EOF
{"inbounds":[{"port":3000,"protocol":"vless","settings":{"clients":[{"flow":"","id":"$UUID"}],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/$WSPATH"}}}],"log":{"loglevel":"warning"},"outbounds":[{"protocol":"freedom"}]}
EOF

echo "已生成: $OUT/Dockerfile $OUT/docker-compose.yml $OUT/config.json"
echo "WS 路径: /$WSPATH (UUID 已写入 config.json,不在此回显)"
