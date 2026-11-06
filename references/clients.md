# 客户端自选:按喜好挑,不替用户定

## 原则

- 先问用户用什么客户端,没偏好默认 v2rayN/v2rayNG。
- 输出是标准 `vless://` 链接 + 二维码 + 参数明细,三件套本身不绑定客户端。

## 各客户端导入方式

| 客户端 | 平台 | 导入方式 | 备注 |
|---|---|---|---|
| v2rayN | Windows | 粘贴 vless 链接 / 扫码 | 分流与 TUN 排查见 [v2rayn-client.md](v2rayn-client.md) |
| v2rayNG | Android | 扫码 / 粘贴链接 | 手机测速用它 |
| NekoBox | Android | 粘贴链接 / 扫码 |  |
| Streisand / FoXray | iOS / macOS | 粘贴链接 / 扫码 |  |
| sing-box | 全平台 | 粘贴链接 / 导入 JSON |  |
| Clash Verge / Mihomo | Win / macOS / Linux | 订阅链接或手动写 YAML 代理配置 | **vless 链接不能直接导入**,用参数明细手动填 UUID/地址/端口/WS 路径/TLS,或走订阅转换 |

## 注意

- Clash 系用户不要硬推链接导入,给参数明细让他们自己填代理配置。
- 分流排查只对 v2rayN 写过完整手册([v2rayn-client.md](v2rayn-client.md));其他客户端的分流/TUN 问题按各自文档处理,不要把 v2rayN 的结论套过去。
