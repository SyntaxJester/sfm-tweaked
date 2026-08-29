# sfm-tweaked

Magisk / KernelSU / APatch 模块 **神秘啊神秘（SingBox_For_Magisk）** 的配置层二改版。
可直接刷入，也可以只取配置文件覆盖到已有安装。

改的是配置和规则集：修掉 5 个已经 404 的规则源、规则集从 18 个补到 38 个、
订正几处会静默漏流量的路由与 DNS 逻辑、给 tun 补上组播排除。
另外附一个不需要 root 就能跑的配置校验器。

> 三个二进制（`singBox` / `bundle` / `converter`）和所有安装脚本**原样未动**，
> 与原版逐字节一致（有 sha256 比对，见下）。

---

## 原作者

| | |
|---|---|
| 原模块 | 神秘啊神秘 / `SingBox_For_Magisk` |
| **原作者** | **Puer_Nya** — GitHub [@PuerNya](https://github.com/PuerNya) |
| 基于原版 | `version=202408160739` / `versionCode=8` |
| 本版本 | `version=202608292125` / `versionCode=9` |
| 内核 | [PuerNya/sing-box](https://github.com/PuerNya/sing-box) fork，基线 `1.10.0-alpha.29-067c81a7` |

**模块的全部功能实现都是原作者的作品** —— 定制 sing-box 内核、Node.js 面板、
配置转换器、安装脚本、Web 前端、附带 App。本仓库一行都没改。

我（[@SyntaxJester](https://github.com/SyntaxJester)）只改了配置层：
换规则源、加规则集、改路由和 DNS 规则的写法、补 tun 入站字段，再写了个校验脚本。
没有任何逆向修改或功能重写。

原模块未附带许可证文件。这里连同二进制一起打包，纯粹是为了让二改版能直接刷入使用。
**如原作者认为不妥（包括但不限于二进制的再分发、命名、或任何其他方面），请开 issue 或
以任意方式联系，我会立刻删除相关内容或整个仓库。**

完整署名与上游致谢见 [CREDITS.md](CREDITS.md)。

---

## 与原版的差异

改动只有 7 个文件，其余 **58 个文件与原版 sha256 完全一致**：

| 文件 | 变化 |
|---|---|
| `sfm/src/baseConfig.yaml` | 主要改动，见下 |
| `sfm/RuleProviders/路由后台-域名.json` | **新建**，48 条 |
| `sfm/RuleProviders/推送服务-域名.json` | 4 → 27 条 |
| `sfm/RuleProviders/强制直连-域名.json` | 9 → 33 条 |
| `sfm/RuleProviders/强制代理-域名.json` | 3 → 31 条 |
| `sfm/RuleProviders/跳过覆写.json` | 7 → 32 条 |
| `module.prop` | `version` / `versionCode` / 署名，见下 |
| `tools/`、`docs/` | **新增**，校验器与文档（不参与刷入） |

未改动的包括：`sfm/singBox`、`sfm/bundle`、`sfm/converter`、`handle`、`keycheck`、
`base.apk`、`customize.sh`、`service.sh`、`post-fs-data.sh`、`uninstall.sh`、
`webroot/`、`sfm/Dashboard/`、`sfm/src/maho/`、`sfm/src/config.yaml`、
`sfm/src/FileProviders/`、`META-INF/`，以及 16 个 `.srs` 规则集文件。

### module.prop 的改动

```diff
-name=神秘啊神秘
-version=202408160739
-versionCode=8
-author=Puer_Nya
+name=神秘啊神秘（二改版）
+version=202608292125
+versionCode=9
+author=Puer_Nya（二改：SyntaxJester）
```

改 `version` / `versionCode` 是为了让模块管理器能区分二改版和原版，
并保证覆盖刷入时不会被 `customize.sh` 里的
`elif [ ${MODULEVERSION} -lt 8 ]` 判定成「旧 UI」而多做一次管理器缓存清理。

`id` 保持 `SingBox_For_Magisk` 不变 —— 改了会被当成另一个模块，
数据目录 `/data/adb/sfm` 的增量更新逻辑会失效。

`author` 保留原作者在前，二改者在括号内，模块列表里一眼能看出来源。
`description` 保持原文不动 —— `service.sh` 会用 `sed -i "6c..."` 按**行号**改写它，
所以第 6 行必须继续是 `description=`。

想自己核对未改动的部分：

```bash
# 在仓库根目录，一条命令校验原作者的 58 个文件
sha256sum -c UPSTREAM_SHA256.txt
```

全是 `OK` 就说明没动过。详细说明见 [docs/VERIFY.md](docs/VERIFY.md)。

---

## 改了什么，为什么

### 1. 五个规则源已经 404 —— 这是最要紧的一条

`UptonEdward/sing-geosite` 仓库整个被删了（GitHub API 返回 404 Not Found），
原配置里五个 `rule_set` 全部拉不动：
`海外公司-域名`、`海外公司-大陆服务-域名`、`大陆相关-域名`、`大陆相关-海外服务-域名`、`苹果-域名`。

后果分两种：

- **全新安装**（`cache.db` 里没有缓存）：`RemoteRuleSet.StartContext` 会
  `return E.Cause(err, "initial rule-set: ", tag)` —— **整个 sing-box 起不来**
- **老机器**：靠 `cache_file` 里的旧副本活着，但规则永久停在失效那天，之后每次更新都静默失败

全部换到 [`lyc8503/sing-box-rules`](https://github.com/lyc8503/sing-box-rules)。
选它是因为它是 SagerNet 官方 `sing-geosite` 的镜像 + 增量（1892 vs 官方 1873 个 srs），
且 geosite/geoip 双分支齐全 —— 官方 `sing-geoip` 只有国家码，没有 `private`。
实测最后提交时间与官方同日。

### 2. `geosite-cn@!cn` 和 `geolocation-!cn@cn` 这两个名字根本不存在

比对过 4 个仓库的完整文件树（官方 1873 个、lyc8503 1892 个、MetaCubeX 3792 个），
`@cn` / `@!cn` 属性标签挂在 `category-companies` 这一族上，
不挂在 `geolocation-!cn` / `cn` 上 —— 因为后两者本身是「地理归属」列表，不带属性标签。

正确对应物：`geosite-category-companies@cn` 和 `geosite-category-companies@!cn`。
这两条从写出来那天就是错的，只是因为整个仓库 404 所以没人发现。

### 3. `fc70::/10` 是笔误，但不能改用 `ip_is_private`

原来的保留地址规则：

```yaml
ip_cidr: [0.0.0.0/8, 127.0.0.0/8, 192.168.0.0/16, ::/128, ::1/128, fc70::/10, fe80::/10]
```

`fc70::/10` 不是任何标准保留段（ULA 是 `fc00::/7`），写了等于没写。

但改成 `ip_is_private: true` 会踩另一个更隐蔽的坑：它的实现是 `!N.IsPublicAddr(addr)`，
而 Go 的 `Addr.IsPrivate()` 对 v6 判定的是 `fc00::/7` ——
本配置 FakeIP 的 v6 池 `dns.fakeip.inet6_range: fc00::/18` **正好落在里面**。

启用后，FakeIP 模式下没命中任何域名规则的 v6 连接，会在 IP 阶段被判成「局域网」直接走
`本机直连`。表现是部分站点 IPv6 走漏，且没有任何报错。

改法：显式列 13 个 CIDR，v6 侧只写 `fd00::/8`（真实在用的 ULA），避开 `fc00::/8`。
同时补上原版漏掉的 `10.0.0.0/8`、`172.16.0.0/12`、`100.64.0.0/10`（运营商 CGNAT）、
`169.254.0.0/16`、`224.0.0.0/4`、`ff00::/8`。

### 4. tun 没有任何 route 排除，局域网发现协议全被黑洞

原 tun 只有 `strict_route: true` + `auto_route: true`。
`strict_route` 在 Linux 的语义是「Route all connections to tun」——
mDNS(5353)、SSDP(1900)、NDP、DHCP 这些走组播/链路本地地址的包全被吸进 tun，
而内核对组播地址没有处理路径。结果：投屏、AirPlay、DLNA、打印机发现全失效。

补上：

```yaml
route_exclude_address:
  - 169.254.0.0/16    # 链路本地（DHCP 前、APIPA）
  - 224.0.0.0/4       # 组播：mDNS 224.0.0.251、SSDP 239.255.255.250
  - 255.255.255.255/32
  - fe80::/10         # v6 链路本地（NDP、mDNS v6）
  - ff00::/8          # v6 组播
```

**这里刻意没加 `192.168.0.0/16` 和 `10.0.0.0/8`**，这点跟直觉相反：
网关 DNS（`192.168.1.1:53`）必须继续进 tun，才能被 route 第一条规则劫持到 `域名解析` 出站。
把 `192.168.0.0/16` 排掉会让 DNS 查询绕过 tun 直达网关，FakeIP 和全部 DNS 分流整体失效。
局域网单播流量交给 route 侧的「保留地址直连」处理，效果一样但不牺牲 DNS 劫持。

（也评估过 1.10 的 `route_exclude_address_set` —— 能直接喂 `geoip-cn` 这种规则集，
但它要求 `auto_redirect` + nftables，且文档明确写「Conflict with `route.default_mark`」，
本模块又依赖 `default_mark: 2333` 做 tproxy 兼容，所以用不了。）

### 5. 三个本地 srs 文件白占位置

`哔哩哔哩-域名.srs`、`哔哩哔哩2-域名.srs`、`哔哩哔哩-PCDN｜MCDN-域名.srs`
在 `RuleProviders/` 里存在，但 `route.rule_set` 里没有声明 —— 从未被加载过。
同族的 `虎牙-PCDN｜MCDN-域名` 有声明有使用，就是漏了哔哩哔哩这三个。已补齐。

### 6. HTTPDNS 只拦了十来个域名

原本只有本地那个 480B 的小 srs。加上 `geosite-category-httpdns-cn`（100 条，
覆盖阿里/百度/华为/腾讯的 HTTPDNS 端点）。
HTTPDNS 不拦干净，App 会绕过所有 DNS 规则直接拿真实 IP，分流形同虚设。

### 规模变化

| | 原版 | 本仓库 |
|---|---|---|
| `route.rule_set` | 18 | **38**（27 remote + 11 local） |
| `route.rules` | 19 | **22**（16 启用 + 6 个 `enabled: false` 开关位） |
| `dns.rules` | 19 | **22** |
| 本地规则集条目 | 30 | **170** |

新增的 20 个规则集：私有网络（域名+IP）、路由后台、NTP、HTTPDNS 扩展、
谷歌/微软/亚马逊大陆分站、腾讯/阿里/字节/B站海外分站、海外 CDN 国内节点、
游戏平台国服、AI 服务、IP 归属检测、BT tracker、以及补声明的三个哔哩哔哩。

`update_interval` 按变动频率分档：日更集合 `24h`，
半年不变的（private / ntp / httpdns / games@cn / ip-geo-detect）用 `168h`，
少 26 次无谓的 GitHub 请求/天。

### 6 个默认关闭的开关位

在面板里把 `enabled` 改成 `true` 就生效，不用自己写规则：

| 开关 | 什么时候打开 |
|---|---|
| `protocol: bittorrent` 拦截 | 免流卡、或家宽怕被投诉 |
| BT tracker 域名拦截 | 与上一条配套 |
| `ip_version: 6` 拦截 | v6 环境有问题时 |
| `protocol: quic` 拦截 | 全局拦 QUIC |
| `protocol: dtls` 拦截 | 原版就有 |
| **国内 QUIC 拦截** | **国内出口选了「大厂羊毛」这类 http 节点时** |

最后那个值得说一下：`大厂羊毛` 是 `type: http` 出站，**只承载 TCP**。
选它做国内出口时所有 UDP/QUIC 直接黑洞，表现为 B 站、微博一直转圈。
打开这条把国内 QUIC 拦掉，客户端会自动回落 TCP。

---

## 安装

### 方式一：直接刷入（推荐）

从 [Releases](../../releases) 下载 zip，用 Magisk / KernelSU / APatch 刷入。

zip 里附带了 `CREDITS.md`、`LICENSE` 和 `UPSTREAM_SHA256.txt` ——
刷入前可以先解开核对原作者的 58 个文件没被动过：

```bash
unzip -q SingBox_For_Magisk-tweaked-*.zip -d /tmp/chk && cd /tmp/chk
sha256sum -c UPSTREAM_SHA256.txt | grep -cv ': OK$'   # 应输出 0
```

前置条件与原版相同：

- **arm64** 设备
- 装了 **Termux**，且在 Termux 里 `pkg install nodejs aapt`
- 从 Magisk/KernelSU/APatch app 刷（不支持 Recovery）

刷入后重启，访问面板（KernelSU/APatch 用 WebUI，Magisk 用自动安装的 App），
初始密码 `node`。

**覆盖刷入的注意事项** —— 原版 `customize.sh` 在检测到 `/data/adb/sfm` 已存在时会走
「增量更新」分支，其中这两行会**把你现有的配置还原回去**：

```sh
cp -rf ${DATADIR}.old/${TIMESTAMP}/RuleProviders/*.json ${DATADIR}/RuleProviders/
cp -f  ${DATADIR}.old/${TIMESTAMP}/src/baseConfig.yaml  ${DATADIR}/src/baseConfig.yaml
```

这是原作者的设计（保护用户配置不被模块更新覆盖），我没有改动它。
所以如果你已经装过原版，刷入本 zip 后配置还是旧的，需要手动再覆盖一次 ——
用下面的方式二，或者先卸载原模块（`uninstall.sh` 会删掉 `/data/adb/sfm`）再全新刷入。

### 方式二：只覆盖配置

已经在用原版、不想重刷模块的话：

```bash
su

# 必须先停面板 —— baseConfig.yaml 是它的工作缓存，
# 面板每次保存配置都会 writeFileSync + rename 覆盖它，不停进程直接改会被写回的内容盖掉
pkill -f 'node /data/adb/sfm/bundle'

# 备份
cp /data/adb/sfm/src/baseConfig.yaml /data/adb/sfm/src/baseConfig.yaml.bak
cp -r /data/adb/sfm/RuleProviders /data/adb/sfm/RuleProviders.bak

# 覆盖
cp sfm/src/baseConfig.yaml /data/adb/sfm/src/
cp sfm/RuleProviders/*.json /data/adb/sfm/RuleProviders/

# 内核自校验（这一步会真的解析 box.json）
/data/adb/sfm/singBox check -D /data/adb/sfm -c box.json

# 重启面板：最省事是 reboot；不想重启就手动拉起（node 在 termux 里，环境变量必须带）
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:$PATH
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
nohup node /data/adb/sfm/bundle --enable-source-maps >/dev/null 2>/data/adb/sfm/src/log/run.log &
pidof node && pidof singBox
```

### 首次启动会下载规则集

27 个远程规则集，约 3MB，走 `download_detour: 国外出口` ——
**必须先有一个能用的国外节点**，否则 `initial rule-set` 失败、内核起不来。
节点还没配好的话，先把这些 `rule_set` 的 `type` 临时改成 `local` 跑起来再说。

### 回滚

```bash
su
pkill -f 'node /data/adb/sfm/bundle'
cp /data/adb/sfm/src/baseConfig.yaml.bak /data/adb/sfm/src/baseConfig.yaml
rm -rf /data/adb/sfm/RuleProviders && mv /data/adb/sfm/RuleProviders.bak /data/adb/sfm/RuleProviders
rm -f /data/adb/sfm/src/cache.db   # 清掉规则集缓存，避免新旧混用
reboot
```

---

## 配置校验器

```bash
python3 tools/validate_baseconfig.py sfm/src/baseConfig.yaml tools/kernel_fields.txt
```

```
=== 校验 sfm/src/baseConfig.yaml
rule_set: 38 个, route.rules: 22 条, dns.rules: 22 条, inbounds: 3, outbounds: 7

✅ 无阻断性错误
```

它模拟 `bundle` 生成 `box.json` 的流程，再按内核字段白名单核对。
好处是不需要 root、不需要真机，改配置的当场就能验。

检查项：

- `notice` / `enabled` 是否写在 `bundle` 会剥离的位置
- 所有键名是否在内核 372 个 JSON tag 白名单内
- `rule_set` / `outbound` / `server` / `inbound` / `detour` / `download_detour` / `final`
  的 tag 引用是否存在，selector 的 `outbounds` 嵌套是否有效
- `rule_set` tag 重复、`format` 与 `path` 后缀是否匹配、remote 是否缺 `url`
- 哪些 `rule_set` 定义了但没人引用（白下载）
- `route.ip_rules` 存在就报错（见下）

`tools/kernel_fields.txt` 是从 `sfm/singBox` 提取的字段全集：

```bash
strings -n 6 sfm/singBox | grep -oE 'json:"[a-zA-Z0-9_,-]+"' \
  | sed 's/json:"//; s/"$//' | tr ',' '\n' \
  | grep -vE '^(omitempty|-)$' | sort -u
```

CI 每次改配置都会自动跑这个校验，外加 JSON 语法检查和**远程规则源可用性探测** ——
这次踩的坑（仓库消失而无感知）就靠最后那步兜。

---

## 自己改配置前先看这两条

### `notice` 不能随便写

`bundle` 的 `$4()` 只在这些位置剥离 `notice`：

```
log / ntp / dns / dns.fakeip / dns.servers[] / dns.rules[]
inbounds[] / outbounds[] / route / route.geoip / route.geosite / route.rules[]
experimental / experimental.clash_api / experimental.v2ray_api(.stats)
```

**`route.rule_set[]` 不在列表里** —— 在规则集条目里写 `notice` 会让内核报
`json: unknown field "notice"`，整个配置起不来（内核用 `DisallowUnknownFields` 解析）。
`dns.rules[].fallback_rules[]` 和 logical 子规则 `route.rules[].rules[]` 里同样不能写。

### `route.ip_rules` 不能用

`bundle` 的 `n4()` 里写的是：

```js
Array.isArray(h.route.ip_rules) ? h.route.rules = h.route.ip_rules.filter(...) : ...
```

赋给了 `h.route.rules`（而非 `ip_rules`）。一旦在 baseConfig 里写了 `route.ip_rules`，
原有的 `route.rules` 会被**整体覆盖丢失**。

这是模块的 bug，但改它得动 `bundle`（esbuild 压缩产物），
而且改完模块一更新就没了，不划算 —— 所以只在这里提醒，校验器会检出这种写法。

---

## 关于内核版本

模块内核是 PuerNya fork 的 `building` 分支 HEAD（`067c81a7`，2024-08-15），
基线 `1.10.0-alpha.29`。官方 sing-box 现在已经是 `v1.13.20`。

**这个内核不能升级，也不需要为此焦虑。** 简要说明：

- fork 的 `building` 分支本身就停在 2024-08-15，之后没有更新
- fork 的其它 32 个分支里有更新的（`dev-next` 2026-01、`respond-fix` 2026-04），
  但**没有一个带模块必需的专有字段** —— 它们是跟随上游的 feature 分支，
  `building` 才是把专有功能合起来出包的分支
- 换官方内核的话，本配置有 **62 处结构性改写**（1.11 起 `outbound` → `action`，
  1.12 起 DNS servers/rules 重构）外加 **21 处 fork 专有字段无法翻译**
  （`fallback_rules` / `sniff_override_rules` / `providers` 等官方根本没有）
- `bundle` 面板生成 `box.json` 的整套流水线也是按 1.10 的 schema 写的，
  它不认识 `action` / `domain_resolver` / `endpoints` 这些新概念

安全方面查过了：sing-box 唯一的公开 CVE（CVE-2023-43644，SOCKS 认证绕过）
影响 `< 1.5.0-rc.5`，本内核不受影响。真正的风险点是配置里的开放代理，
见下面的安全提示。

需要官方新特性（AnyTLS、Tailscale、kTLS 等）请换跟随上游的客户端，
在这个模块上折腾内核版本走不通。

完整分析、含每一步的复核命令，见 [docs/KERNEL.md](docs/KERNEL.md)。

---

## 安全提示

`mixed` 入站是 `listen: '::'` 且没有 `users` —— 同一 Wi-Fi 下任何设备都能免密码
把你当代理跳板。在公共 Wi-Fi 或不可信网络里这是实打实的开放代理。

**我没有擅自改掉**（有人确实靠这个给电视盒子、PC 用），只在配置的 `notice` 里写了三种处置：

- 只给本机用 → `listen: 127.0.0.1`
- 共享但要密码 → 加 `users: [{username: xx, password: yy}]`
- 保持现状 → 确认你在可信网络里

---

## 未验证的部分

所有结论来自：`singBox` 二进制的字段提取、上游 sing-box / sing-tun / sing 源码比对、
以及每个规则源 URL 的实际 HTTP 探测（各重试 5 次）。

**没有在真机上跑过。** 开发环境是 PRoot Alpine 沙盒，`singBox` 需要
`/system/bin/linker64` 跑不起来，`/data/adb` 也不可见。
内核层面的最终确认请自己跑一次 `singBox check`。

遇到问题欢迎开 issue，附上 `/data/adb/sfm/src/log/box.log`（内核）和
`run.log`（面板）会更好定位。

---

## 许可

由我编写的部分（`sfm/src/baseConfig.yaml` 的修改、`sfm/RuleProviders/*.json`、
`tools/`、文档）以 MIT 发布，见 [LICENSE](LICENSE)。

**原模块不在此列。** `SingBox_For_Magisk` 的版权归 Puer_Nya，
其许可条款由原作者决定，本仓库无权代为授权，也不主张任何权利。
详见 [CREDITS.md](CREDITS.md)。
