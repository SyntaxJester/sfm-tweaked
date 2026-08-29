# sfm-config-tweaks

给 Magisk 模块 **神秘啊神秘（SingBox_For_Magisk）** 用的一套配置层二次修改：修掉失效的规则源、补齐规则集、订正几处会静默漏流量的路由/DNS 逻辑，并附一个不需要 root 就能跑的配置校验器。

> **这不是一个独立模块，也不是原模块的分支。**
> 这里只有配置文件（`baseConfig.yaml`）、本地规则集 JSON 和一个校验脚本，
> 需要配合原模块使用。原模块本身请从原作者处获取。

---

## 原作者与来源

| | |
|---|---|
| 原模块 | 神秘啊神秘 / `SingBox_For_Magisk` |
| 原作者 | **Puer_Nya**（GitHub [@PuerNya](https://github.com/PuerNya)） |
| 被修改的版本 | `version=202408160739` / `versionCode=8` |
| 内核 | [PuerNya/sing-box](https://github.com/PuerNya/sing-box) fork，基线 `1.10.0-alpha.29-067c81a7` |

模块的全部功能实现 —— 面板（`bundle`）、配置转换器（`converter`）、定制内核（`singBox`）、
安装脚本、附带 App —— **都是原作者 Puer_Nya 的作品**。本仓库没有参与其中任何一部分。

本人（[@SyntaxJester](https://github.com/SyntaxJester)）只做了配置层面的二改：换规则源、
加规则集、改路由和 DNS 规则的写法、补 tun 入站字段，再写了个校验脚本。
不涉及任何逆向修改或功能重写。

**本仓库不包含、不再分发原模块的任何二进制或脚本。** 原模块未附带许可证文件，
所以这里只放我自己写的内容，避免越界。你需要自备原模块。

如果原作者认为此仓库的存在方式不妥（包括但不限于命名、引用方式、配置结构的相似度），
请开 issue 或直接联系，我会立刻按要求调整或删库。

### 上游相关项目致谢

| 项目 | 用途 |
|---|---|
| [SagerNet/sing-box](https://github.com/SagerNet/sing-box) | 内核上游 |
| [lyc8503/sing-box-rules](https://github.com/lyc8503/sing-box-rules) | 本次替换后的主力规则集源 |
| [SagerNet/sing-geosite](https://github.com/SagerNet/sing-geosite) | 官方规则集（上游数据） |
| [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) | geoip cn |
| [CHIZI-0618/v2ray-rules-dat](https://github.com/CHIZI-0618/v2ray-rules-dat) | tiktok / bytedance / huya / douyu |
| [Yuu518/sing-box-rules](https://github.com/Yuu518/sing-box-rules) | 广告拦截（沿用原配置的选择） |
| [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) | 上述 geosite 的原始数据源 |

---

## 为什么要改

原配置在当前时间点存在几个实际问题，其中第一个会直接导致内核起不来：

**1. 五个规则源已经全部 404。** `UptonEdward/sing-geosite` 仓库整个被删了，
`海外公司-域名`、`海外公司-大陆服务-域名`、`大陆相关-域名`、`大陆相关-海外服务-域名`、`苹果-域名`
五个 `rule_set` 全部拉不动。首次启动（`cache.db` 无缓存）时
`RemoteRuleSet.StartContext` 会 `return E.Cause(err, "initial rule-set: ", tag)`，
整个 sing-box 启动失败；已经跑过的机器靠旧缓存活着，但规则永久停在失效那天。

**2. `geosite-cn@!cn` 和 `geolocation-!cn@cn` 这两个名字在任何主流仓库都不存在。**
比对过 4 个仓库的完整文件树（官方 1873 个 srs、lyc8503 1892 个、MetaCubeX 3792 个），
属性标签 `@cn` / `@!cn` 挂在 `category-companies` 这一族上，不挂在 `geolocation-!cn` / `cn` 上。
正确对应物是 `geosite-category-companies@cn` 和 `@!cn`。

**3. `fc70::/10` 是笔误，且不能简单改用 `ip_is_private`。**
`fc70::/10` 不是任何标准保留段（ULA 是 `fc00::/7`）。但改成 `ip_is_private: true` 会踩另一个坑：
它的实现是 `!N.IsPublicAddr(addr)`，而 Go 的 `Addr.IsPrivate()` 对 v6 判定 `fc00::/7` ——
本配置 FakeIP 的 v6 池 `inet6_range: fc00::/18` 正好落在里面。
启用后，FakeIP 模式下未命中域名规则的 v6 连接会在 IP 阶段被判成局域网直接走直连，
静默漏流量且无任何报错。

**4. tun 没有任何 route 排除，局域网发现协议全被黑洞。**
`strict_route: true` 在 Linux 的语义是「Route all connections to tun」，
mDNS(5353)、SSDP(1900)、NDP、DHCP 这些走组播/链路本地地址的包全被吸进 tun，
而内核对组播地址没有处理路径 —— 投屏、AirPlay、DLNA、打印机发现全部失效。

**5. 三个本地 `.srs` 文件白占位置。**
`哔哩哔哩-域名.srs`、`哔哩哔哩2-域名.srs`、`哔哩哔哩-PCDN｜MCDN-域名.srs` 在 `RuleProviders/`
里存在，但 `route.rule_set` 里没有声明，等于从未被加载。

**6. HTTPDNS 只拦了十来个域名。** 原本只有本地那个 480B 的小 srs。
HTTPDNS 不拦干净，App 会绕过所有 DNS 规则直接拿真实 IP，分流形同虚设。

完整分析（含每个 URL 的实测状态、内核字段的取证方法、`bundle` 的行为细节）
见 [docs/CHANGES.md](docs/CHANGES.md)。

---

## 改了什么

| | 原版 | 本仓库 |
|---|---|---|
| `route.rule_set` | 18 | **38**（27 remote + 11 local） |
| `route.rules` | 19 | **22**（16 启用 + 6 个 `enabled: false` 开关位） |
| `dns.rules` | 19 | **22** |
| 本地规则集条目 | 30 | **170** |

**规则提供者** — 修好 5 个失效 URL（统一换到 `lyc8503/sing-box-rules`），
新增 20 个规则集（私有网络、路由后台、NTP、HTTPDNS 扩展、各大厂大陆/海外分站、AI 服务、
IP 归属检测、BT tracker），补上三个漏声明的本地 srs。
`update_interval` 按变动频率分档：日更集合 `24h`，半年不变的（private/ntp/httpdns/games@cn）用 `168h`。

**路由** — 新增「路由后台+私有网络恒直连」「NTP 走直连」，重写保留地址规则（7 个 CIDR → 13 个），
HTTPDNS/PCDN 拦截扩容，stun 拦截加哔哩哔哩，
新增 3 个默认关闭的开关位（BT 流量拦截、公共 tracker 拦截、国内 QUIC 拦截）。

最后那个开关是针对「大厂羊毛」出站的：`type: http` 只承载 TCP，
选它做国内出口时所有 UDP/QUIC 直接黑洞，表现为 B 站/微博一直转圈 ——
打开这条把国内 QUIC 拦掉，客户端会自动回落 TCP。

**DNS** — 新增内网后缀（`.lan`/`.local`/`.home.arpa` 等）交给网关 DNS 解析、
NTP 走 `direct-dns` 且 `rewrite_ttl: 30`，`fallback_rules` 补 `私有网络-IP`，
`fakeip.exclude_rule` 补内网后缀。

注意 `路由后台-域名` 里的 `miwifi.com` / `tplogin.cn` / `asusrouter.com` 是**真实公网域名**，
不能丢给网关解析（网关自己也解析不出来），所以它们走 `direct-dns`，
解析出的内网 IP 再由 route 侧的保留地址规则送去直连。

**入站** — 三个入站的 `sniff_override_rules` 统一补上 `路由后台-域名` + `私有网络-域名`；
tun 新增 `route_exclude_address`：

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

---

## 校验器

```bash
python3 tools/validate_baseconfig.py src/baseConfig.yaml tools/kernel_fields.txt
```

```
=== 校验 src/baseConfig.yaml
rule_set: 38 个, route.rules: 22 条, dns.rules: 22 条, inbounds: 3, outbounds: 7

✅ 无阻断性错误
```

它模拟 `bundle` 生成 `box.json` 的流程，再按内核字段白名单核对。
相比 `singBox check` 的好处是不需要 root、不需要真机，写配置的当场就能跑。

检查项：

- `notice` / `enabled` 是否写在 `bundle` 会剥离的位置
- 所有键名是否在内核 372 个 JSON tag 白名单内
- `rule_set` / `outbound` / `server` / `inbound` / `detour` / `download_detour` / `final`
  的 tag 引用是否存在，selector 的 `outbounds` 嵌套是否有效
- `rule_set` tag 重复、`format` 与 `path` 后缀是否匹配、remote 是否缺 `url`
- 哪些 `rule_set` 定义了但没人引用（白下载）
- `route.ip_rules` 存在就报错（见下）

`tools/kernel_fields.txt` 是从原模块的 `singBox` 二进制提取的字段全集，
提取方式：

```bash
strings -n 6 singBox | grep -oE 'json:"[a-zA-Z0-9_,-]+"' \
  | sed 's/json:"//; s/"$//' | tr ',' '\n' \
  | grep -vE '^(omitempty|-)$' | sort -u
```

### 两个容易踩的坑

**`notice` 不能随便写。** `bundle` 的 `$4()` 只在这些位置剥离 `notice`：

```
log / ntp / dns / dns.fakeip / dns.servers[] / dns.rules[]
inbounds[] / outbounds[] / route / route.geoip / route.geosite / route.rules[]
experimental / experimental.clash_api / experimental.v2ray_api(.stats)
```

`route.rule_set[]` **不在列表里** —— 在规则集条目里写 `notice` 会让内核报
`json: unknown field "notice"`，整个配置起不来。`dns.rules[].fallback_rules[]` 和
logical 子规则 `route.rules[].rules[]` 里同样不能写。校验器会检出这类错误。

**`route.ip_rules` 不能用。** `bundle` 的 `n4()` 里写的是：

```js
Array.isArray(h.route.ip_rules) ? h.route.rules = h.route.ip_rules.filter(...) : ...
```

赋给了 `h.route.rules`（而非 `ip_rules`）。一旦在 baseConfig 里写了 `route.ip_rules`，
原有的 `route.rules` 会被整体覆盖丢失。

---

## 使用

### 前置

先装好原模块并确认能正常运行（面板打得开、`pidof singBox` 有输出）。
本仓库只替换配置，不解决模块本身的安装问题。

### 部署

```bash
su

# 停面板进程 —— 必须先停
# baseConfig.yaml 是面板的工作缓存，面板每次改配置都会 writeFileSync + rename 覆盖它，
# 不停进程直接改会被写回的内容盖掉
pkill -f 'node /data/adb/sfm/bundle'

# 备份
cp /data/adb/sfm/src/baseConfig.yaml /data/adb/sfm/src/baseConfig.yaml.bak
cp -r /data/adb/sfm/RuleProviders /data/adb/sfm/RuleProviders.bak

# 覆盖
cp src/baseConfig.yaml /data/adb/sfm/src/
cp RuleProviders/*.json /data/adb/sfm/RuleProviders/

# 内核自校验（这一步会真的解析 box.json）
/data/adb/sfm/singBox check -D /data/adb/sfm -c box.json
```

最省事的重启方式是直接 `reboot`。想不重启就手动拉起面板（照抄模块 `service.sh` 的启动方式，
node 来自 termux，环境变量必须带）：

```bash
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:$PATH
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
nohup node /data/adb/sfm/bundle --enable-source-maps \
  >/dev/null 2>/data/adb/sfm/src/log/run.log &

# 确认起来了
pidof node && pidof singBox
```

起不来就看 `/data/adb/sfm/src/log/run.log`（面板日志）和
`/data/adb/sfm/src/log/box.log`（内核日志）。

`RuleProviders/` 里的 5 个 `.srs`（`HTTPDNS-域名`、`虎牙-PCDN｜MCDN-域名`、
`哔哩哔哩-域名`、`哔哩哔哩2-域名`、`哔哩哔哩-PCDN｜MCDN-域名`）是**原模块自带的**，
本仓库不包含也不改动它们，保持原样即可 —— 新配置会正确声明并引用它们。

### 首次启动注意

会下载 27 个远程规则集（约 3MB），走 `download_detour: 国外出口` ——
**必须先有一个能用的国外节点**，否则 `initial rule-set` 失败、内核起不来。
如果节点还没配好，临时把这些 `rule_set` 的 `type` 改成 `local` 先跑起来。

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

## 安全提示

原配置的 `mixed` 入站是 `listen: '::'` 且没有 `users` —— 同一 Wi-Fi 下任何设备都能
免密码把你当代理跳板。在公共 Wi-Fi 或不可信网络里这是实打实的开放代理。

我**没有擅自改掉**（有人确实靠这个给电视盒子/PC 用），只在配置的 `notice` 里写明了三种处置：

- 只给本机用 → `listen: 127.0.0.1`
- 共享但要密码 → 加 `users: [{username: xx, password: yy}]`
- 保持现状 → 确认你在可信网络里

---

## 未验证的部分

所有结论来自：原模块二进制的字段提取、上游 sing-box / sing-tun / sing 源码比对、
以及每个规则源 URL 的实际 HTTP 探测（各重试 5 次）。

**没有在真机上跑过。** 开发环境是 PRoot Alpine 沙盒，`singBox` 需要
`/system/bin/linker64` 跑不起来，`/data/adb` 也不可见。
内核层面的最终确认请自己执行一次 `singBox check`。

如果你在真机上遇到问题，欢迎开 issue 附上 `src/log/box.log` 和 `src/log/run.log`。

## 明确没做的事

- **没动 `bundle` / `converter`** — 都是 esbuild 压缩产物，`route.ip_rules` 那个 bug
  只能改 JS 修，改了模块一更新就没了，不划算。写进文档提醒别用即可
- **没换 `singBox`** — fork 专有字段（`fallback_rules` / `allow_fallthrough` /
  `accept_result` / `match_all` / `providers` 等）在上游 sing-box 里不存在，
  换官方内核这套配置直接废掉
- **没有重新分发原模块** — 见上文「原作者与来源」

## 许可

本仓库中由我编写的内容（`src/baseConfig.yaml` 的修改部分、`RuleProviders/*.json`、
`tools/validate_baseconfig.py`、文档）以 MIT 发布，见 [LICENSE](LICENSE)。

**这不覆盖原模块。** 原模块（`SingBox_For_Magisk`）的版权归 Puer_Nya，
其许可条款由原作者决定，本仓库无权代为授权。
`src/baseConfig.yaml` 的整体结构派生自原模块自带的配置模板，
若原作者对此有异议请告知。
