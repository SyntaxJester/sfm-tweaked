# 署名与致谢 / Credits

## 原作品

本仓库是 Magisk 模块 **神秘啊神秘（`SingBox_For_Magisk`）** 的配置层二改版，
不是原创作品。

- **原作者**：Puer_Nya — GitHub [@PuerNya](https://github.com/PuerNya)
- **基于原版**：`version=202408160739`，`versionCode=8`
- **本版本**：`version=202608310745`，`versionCode=10`
- **模块描述**（原文）：借助魔法的力量使用 sing-box 进行代理

### 原作者的作品（本仓库原样收录，未作任何修改）

以下文件与原版 **sha256 完全一致**：

| 文件 | 说明 | 大小 |
|---|---|---|
| `sfm/singBox` | 定制 sing-box 内核（PuerNya fork，基线 1.10.0-alpha.29-067c81a7，aarch64） | 31.9 MB |
| `sfm/bundle` | Node.js 面板 / 配置转换服务（esbuild 打包） | 2.2 MB |
| `sfm/converter` | hjson → yaml 配置迁移工具 | 232 KB |
| `handle` | 应用名缓存生成器（调用 aapt） | 32 KB |
| `keycheck` | 音量键读取（安装时交互） | 8 KB |
| `base.apk` | 附带入口 App（`webapp.shenmi`） | 640 KB |
| `customize.sh` | 模块安装脚本 | — |
| `service.sh` / `post-fs-data.sh` / `uninstall.sh` | 启停与卸载脚本 | — |
| `webroot/index.html` | KernelSU / APatch WebUI 入口 | — |
| `META-INF/` | Magisk 刷机入口 | — |
| `sfm/Dashboard/index.html` | Clash 面板占位 | — |
| `sfm/src/maho/` | Web 面板前端（19 个文件） | — |
| `sfm/src/config.yaml` | 模块运行配置 | — |
| `sfm/src/FileProviders/百度直连.yaml` | 免流节点模板 | — |
| `sfm/RuleProviders/*.srs` | 16 个二进制规则集 | — |
| `sfm/README.md` | 原作者的使用说明 | — |

原模块也自带 `sfm/src/baseConfig.yaml` 配置模板、`RuleProviders/*.json` 规则集
和 `module.prop`，本仓库的同名文件是在其基础上修改的衍生内容。

## 二改者

- [@SyntaxJester](https://github.com/SyntaxJester)

### 改动清单（7 个文件）

| 文件 | 改动 |
|---|---|
| `sfm/src/baseConfig.yaml` | 修 5 个失效 URL、新增 20 个 rule_set、新增 `国内UDP出口` 出站与 TCP/UDP 分离规则、订正保留地址规则、为 tun 补 `route_exclude_address` |
| `sfm/RuleProviders/路由后台-域名.json` | 新建，48 条 |
| `sfm/RuleProviders/推送服务-域名.json` | 4 → 27 条 |
| `sfm/RuleProviders/强制直连-域名.json` | 9 → 33 条 |
| `sfm/RuleProviders/强制代理-域名.json` | 3 → 31 条 |
| `sfm/RuleProviders/跳过覆写.json` | 7 → 32 条 |
| `module.prop` | `version` 202408160739 → 202608310745、`versionCode` 8 → 10、`name` 加「（二改版）」、`author` 加二改者。`id` 与 `description` 保持不变 |
| `tools/`、`docs/`、`.github/` | 新增：配置校验器、内核字段表、文档、CI（均不参与刷入） |

`module.prop` 中 `id` 不改是因为改了会被当成另一个模块，`/data/adb/sfm` 的增量更新逻辑失效；
`description` 不改是因为 `service.sh` 用 `sed -i "6c..."` 按行号改写它，第 6 行必须继续是它。

**未做**：任何逆向修改、功能重写、二进制替换或重新编译。

## 设计参考

`network: tcp` + 独立 UDP 出站这个思路，参考了社区里另一份二改
**「神秘啊神秘（儒雅二改）」v202505252012**（作者署名 `Puer_Nya（儒雅二改）`）。
它在 `route.rules` 里用成对规则把 TCP 与 UDP 分开，让 http 类免流出站只承载 TCP、
UDP 走独立出口，从而避免 UDP 撞上 TCP-only 出站被内核关闭。

本仓库只借用了这个**设计思路**，具体实现是按本仓库的规则结构重写的，
且**没有采用**它的以下部分：

- 它的 `singBox` 内核（1.9 基线，比本仓库的 1.10 更旧，
  会失去 `route_exclude_address` / `auto_redirect`）
- 它内置的 `bin/node`（100 MB）、`bin/aapt`、`bin/ps` 等第三方二进制
- 它的 `ProxyProviders/` 与 `FileProviders/`（含真实机场凭据）
- 它的 `port: [446, 30443]` 之类绑定特定服务的规则

## 上游数据与项目

| 项目 | 作者 / 组织 | 在本仓库中的作用 |
|---|---|---|
| [sing-box](https://github.com/SagerNet/sing-box) | SagerNet | 内核上游；配置字段语义与路由匹配行为的比对依据 |
| [sing-tun](https://github.com/SagerNet/sing-tun) | SagerNet | tun 实现；`route_exclude_address` / `strict_route` 行为的比对依据 |
| [sing](https://github.com/SagerNet/sing) | SagerNet | `IsPublicAddr` 实现，确认 `ip_is_private` 与 FakeIP v6 池重叠问题的来源 |
| [PuerNya/sing-box](https://github.com/PuerNya/sing-box) | PuerNya | 内核 fork；`fallback_rules` / `allow_fallthrough` / `accept_result` / `match_all` / `providers` 等专有字段的定义来源 |
| [lyc8503/sing-box-rules](https://github.com/lyc8503/sing-box-rules) | lyc8503 | 本次替换后的主力规则集源（官方镜像 + 增量，1892 个 srs） |
| [sing-geosite](https://github.com/SagerNet/sing-geosite) | SagerNet | 官方规则集（上述镜像的上游） |
| [meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) | MetaCubeX | `geoip/cn.srs`（沿用原配置的选择） |
| [v2ray-rules-dat](https://github.com/CHIZI-0618/v2ray-rules-dat) | CHIZI-0618 | tiktok / bytedance / huya / douyu（沿用原配置的选择） |
| [Yuu518/sing-box-rules](https://github.com/Yuu518/sing-box-rules) | Yuu518 | 广告拦截（沿用原配置的选择） |
| [domain-list-community](https://github.com/v2fly/domain-list-community) | v2fly | 上述 geosite 规则集的原始数据源 |
| [Termux](https://github.com/termux/termux-app) | Termux | 模块的 node / aapt 运行环境依赖 |

失效的源（记录备查）：`UptonEdward/sing-geosite` 仓库已删除，原配置中 5 个 URL 全部 404。

## 关于二进制再分发

原模块未附带任何许可证文件。本仓库连同 `singBox` / `bundle` / `converter` /
`base.apk` 等二进制一起收录，目的只有一个：让二改版能直接刷入使用，
而不是要求每个用户先去别处找原版再手动拼配置。

对此我的立场：

- 二进制**原样收录，未作任何修改**，可用 sha256 逐个比对
- 全部标注为原作者作品，本仓库不主张任何权利
- 如原作者 Puer_Nya 认为不妥 —— 包括二进制的再分发、命名、
  或配置结构与原模板的相似程度 —— 请通过 issue 或任意渠道告知，
  **将立即删除相关内容或整个仓库**，不需要任何理由

## 许可范围

- 由二改者编写的部分以 MIT 发布（见 `LICENSE`）
- 原模块及其二进制的版权归 Puer_Nya，其许可条款由原作者决定
- `sfm/src/baseConfig.yaml` 派生自原模块自带模板，其原始部分的版权归原作者
- 各规则集数据的版权归其各自项目所有
