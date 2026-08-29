# 署名与致谢 / Credits

## 原作品

本仓库是对下列 Magisk 模块的**配置层二次修改**，不是原创作品，也不是其分支：

- **模块名**：神秘啊神秘（`SingBox_For_Magisk`）
- **原作者**：Puer_Nya — GitHub [@PuerNya](https://github.com/PuerNya)
- **被修改版本**：`version=202408160739`，`versionCode=8`
- **模块描述**（原文）：借助魔法的力量使用 sing-box 进行代理

原模块的以下组成部分**全部由原作者 Puer_Nya 编写**，本仓库不包含、
不修改、也不再分发其中任何一项：

| 文件 | 说明 |
|---|---|
| `sfm/singBox` | 定制 sing-box 内核（PuerNya fork，基线 1.10.0-alpha.29-067c81a7，aarch64） |
| `sfm/bundle` | Node.js 面板 / 配置转换服务（esbuild 打包） |
| `sfm/converter` | Clash → sing-box 规则转换器 |
| `sfm/Dashboard/`、`sfm/src/maho/` | Web 面板前端 |
| `handle`、`keycheck` | 辅助工具 |
| `customize.sh`、`service.sh`、`post-fs-data.sh`、`uninstall.sh` | 模块安装与启动脚本 |
| `base.apk` | 附带的入口 App |
| `module.prop`、`webroot/` | 模块元信息 |

原模块也自带了 `src/baseConfig.yaml` 配置模板和 `RuleProviders/` 规则集，
本仓库的同名文件是在其基础上修改的衍生内容。

## 二改者

- [@SyntaxJester](https://github.com/SyntaxJester)

改动范围仅限配置层：

1. 替换 5 个已失效（HTTP 404）的 `rule_set` URL
2. 新增 20 个规则集声明、补上 3 个漏声明的本地 srs
3. 扩充 4 个本地规则集 JSON、新建 1 个（`路由后台-域名.json`）
4. 修正 `route.rules` 中的保留地址规则（`fc70::/10` 笔误 + `ip_is_private` 与
   FakeIP v6 池 `fc00::/18` 的重叠问题）
5. 为 tun 入站补 `route_exclude_address`
6. `dns.rules` 新增内网后缀分流、NTP 分流
7. 新写校验脚本 `tools/validate_baseconfig.py`

未做任何逆向修改、功能重写或二进制替换。

## 上游数据与项目

| 项目 | 作者 / 组织 | 在本仓库中的作用 |
|---|---|---|
| [sing-box](https://github.com/SagerNet/sing-box) | SagerNet | 内核上游；配置字段语义、路由匹配行为的比对依据 |
| [sing-tun](https://github.com/SagerNet/sing-tun) | SagerNet | tun 实现；`route_exclude_address` 行为的比对依据 |
| [sing](https://github.com/SagerNet/sing) | SagerNet | `IsPublicAddr` 实现，`ip_is_private` 语义的确认来源 |
| [PuerNya/sing-box](https://github.com/PuerNya/sing-box) | PuerNya | 内核 fork；`fallback_rules` 等专有字段的定义来源 |
| [lyc8503/sing-box-rules](https://github.com/lyc8503/sing-box-rules) | lyc8503 | 本次替换后的主力规则集源（官方镜像 + 增量） |
| [sing-geosite](https://github.com/SagerNet/sing-geosite) | SagerNet | 官方规则集（上述镜像的上游） |
| [meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) | MetaCubeX | `geoip/cn.srs`（沿用原配置的选择） |
| [v2ray-rules-dat](https://github.com/CHIZI-0618/v2ray-rules-dat) | CHIZI-0618 | tiktok / bytedance / huya / douyu（沿用原配置的选择） |
| [Yuu518/sing-box-rules](https://github.com/Yuu518/sing-box-rules) | Yuu518 | 广告拦截（沿用原配置的选择） |
| [domain-list-community](https://github.com/v2fly/domain-list-community) | v2fly | 上述 geosite 规则集的原始数据源 |

## 关于许可

原模块未附带任何许可证文件。因此：

- 本仓库**不再分发**原模块的任何二进制或脚本
- 本仓库中由二改者编写的部分以 MIT 发布（见 `LICENSE`）
- `src/baseConfig.yaml` 派生自原模块自带模板，其原始部分的版权归原作者

若原作者 Puer_Nya 认为本仓库的存在方式不妥 —— 包括命名、引用方式、
或配置结构与原模板的相似程度 —— 请通过 issue 或任意渠道告知，
将立即按要求调整或删除。
