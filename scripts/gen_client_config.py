#!/usr/bin/env python3
"""生成 VLESS Reality 客户端配置三件套:分享链接 / 二维码 PNG / 参数明细 Markdown。

仅供学习与自用服务器管理,请遵守所在地法律法规。

用法:
    python gen_client_config.py --uuid <UUID> --host <SERVER_IP> --port 443 \
        --sni www.example.com --pbk <PUBLIC_KEY> --sid <SHORT_ID> \
        --name My-Node --out-dir ./out

生成的文件仅限本人使用,请勿外传、勿提交到任何仓库。
"""

import argparse
import datetime
import os

import qrcode


def build_link(args) -> str:
    params = (
        f"encryption=none&flow=xtls-rprx-vision&security=reality"
        f"&sni={args.sni}&fp=chrome&pbk={args.pbk}&sid={args.sid}&type=tcp"
    )
    return f"vless://{args.uuid}@{args.host}:{args.port}?{params}#{args.name}"


def main() -> None:
    p = argparse.ArgumentParser(description="VLESS Reality 客户端配置生成器(仅供学习)")
    p.add_argument("--uuid", required=True)
    p.add_argument("--host", required=True, help="服务器 IP 或域名")
    p.add_argument("--port", type=int, default=443)
    p.add_argument("--sni", required=True, help="伪装 SNI 域名")
    p.add_argument("--pbk", required=True, help="Reality 公钥 PublicKey")
    p.add_argument("--sid", required=True, help="Reality shortId")
    p.add_argument("--name", default="Reality-Node", help="节点名称")
    p.add_argument("--out-dir", default="./out", help="输出目录")
    args = p.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    link = build_link(args)
    safe_name = "".join(c for c in args.name if c.isalnum() or c in "-_")

    # 1. 二维码(手机 v2rayNG / Shadowrocket 扫码导入)
    qr_path = os.path.join(args.out_dir, f"{safe_name}-qr.png")
    qrcode.make(link).save(qr_path)

    # 2. 分享链接(电脑 v2rayN 从剪贴板/文件导入)
    link_path = os.path.join(args.out_dir, f"{safe_name}-link.txt")
    with open(link_path, "w", encoding="utf-8") as f:
        f.write(link + "\n")

    # 3. 参数明细(仅限本人,勿外传勿提交)
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    md_path = os.path.join(args.out_dir, f"{safe_name}-info.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(
            f"# 节点信息({args.name})\n\n"
            f"> ⚠️ 本文件含服务器与节点敏感信息,**仅限本人使用,勿外传、勿提交任何仓库**。\n\n"
            f"- 生成时间:{ts}\n"
            f"- 地址:{args.host}\n"
            f"- 端口:{args.port}\n"
            f"- UUID:`{args.uuid}`\n"
            f"- SNI:{args.sni}\n"
            f"- PublicKey:`{args.pbk}`\n"
            f"- shortId:`{args.sid}`\n"
            f"- 流控:xtls-rprx-vision | 传输:tcp | 安全:reality\n\n"
            f"## 分享链接\n\n```\n{link}\n```\n"
        )

    print("Generated:")
    for path in (qr_path, link_path, md_path):
        print("  " + os.path.abspath(path))


if __name__ == "__main__":
    main()
