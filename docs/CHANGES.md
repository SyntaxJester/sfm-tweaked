# sfm 规则提供者 / 路由 / 入站 完善说明

针对 `SingBox_For_Magisk`（`神秘啊神秘`）原版 v202408160739 的配置层改造，
本版本 `version=202608312000` / `versionCode=11`。
只改配置与规则文件，`bundle` / `converter` / `singBox` 三个二进制不动。

> 原模块作者：**Puer_Nya**（[@PuerNya](https://github.com/PuerNya)）。
> 本文档只记录二改内容，模块本身的全部实现均为原作者作品，详见 [CREDITS.md](../CREDITS.md)。

内核信息（从二进制实测确认，非猜测）：

- `singBox` = PuerNya fork，基线 `1.10.0-alpha.29-067c81a7`，aarch64、动态链接 `/system/bin/linker64`
- fork 专有字段确实存在于二进制：`fallback_rules` / `allow_fallthrough` / `accept_result` /
  `match_all` / `providers` / `use_all_providers` / `outbound_providers` / `sniff_override_rules` /
  `outbound_override` — 所以这些写法可以放心用
- 内核用 `DisallowUnknownFields` 解析 `box.json`，多一个键就整体启动失败
- `notice` **不在**内核字段表里，靠 `bundle` 的 `$4()` 剥离，只在固定位置生效（详见下面「notice 能写在哪」）

---

## 一、原配置里的实际问题

### 0. 免流时 UDP 被内核直接关掉，且白跑流量

免流节点几乎都是 `type: http`。这个内核里 http 出站只声明了 TCP：

```go
// outbound/http.go:38
network: []string{N.NetworkTCP}
// outbound/http.go:65
func (h *HTTP) ListenPacket(ctx, destination) (net.PacketConn, error) {
    return nil, os.ErrInvalid
}
```

UDP 命中它的时候：

```go
// route/router.go:1272
if !common.Contains(detour.Network(), N.NetworkUDP) {
    return E.New("missing supported outbound, closing packet connection")
}
```

**直接关连接，没有任何回退机制。**

原配置（以及本仓库 202608292125 之前的版本）里 `route.rules` 一条都没区分
TCP / UDP —— 国内流量不分协议全送 `国内出口`。一旦那里挂了 http 免流节点：

| 受影响 | 表现 |
|---|---|
| 微信 / QQ 语音视频 | 连不上、一直呼叫中 |
| 手游 UDP 长连接 | 掉线、460 延迟 |
| 网页 QUIC（HTTP/3） | 失败后才回落 TCP，"转圈半天" |
| DNS over QUIC | 解析失败 |

**最反直觉的一点**：UDP 被关后客户端普遍会重试 TCP，
而这些重试连接**不再经过原来那条免流规则**（已经过了那一跳），
按普通计费走掉 —— 想省的流量反而漏了。

用脚本核对过改动前的状态：

```
启用的 route.rules   16 条
带 network 限定       0 条        ← 问题所在
送进 selector 的规则   6 条，全部 TCP+UDP 混走
```

改法见下文「三、改了什么 / 入站与出站」。

### 1. 三个规则源已经 404，`广告拦截` 之外的 geosite 全线拉不动

实测（当前时间点，每个 URL 重试 5 次）：

| tag | 原 URL | 结果 |
|---|---|---|
| 海外公司-域名 | `UptonEdward/sing-geosite` geolocation-!cn | **404** |
| 海外公司-大陆服务-域名 | `UptonEdward/sing-geosite` geolocation-!cn@cn | **404** |
| 大陆相关-域名 | `UptonEdward/sing-geosite` cn | **404** |
| 大陆相关-海外服务-域名 | `UptonEdward/sing-geosite` cn@!cn | **404** |
| 苹果-域名 | `UptonEdward/sing-geosite` apple | **404** |

`UptonEdward/sing-geosite` 仓库整个已删除（API 查询返回 404 Not Found）。

后果分两种情况：

- **首次启动**（cache.db 里没有缓存）：`RemoteRuleSet.StartContext` 会 `return E.Cause(err, "initial rule-set: ", tag)` — 整个 sing-box 起不来
- **已经跑过一次**：靠 `cache_file` 里的旧副本活着，但规则永久停在 404 那天，之后所有更新静默失败

`大陆相关-IP` 用的 `MetaCubeX/meta-rules-dat` 还在（实测 200，36KB）；
`CHIZI-0618` 的 tiktok/bytedance/huya/douyu 也都还在（200）。

### 2. `geosite-cn@!cn` 和 `geolocation-!cn@cn` 这两个名字在任何主流仓库都不存在

排查了 4 个仓库的完整文件树：

- `SagerNet/sing-geosite@rule-set`：1873 个 srs，`!cn@` 只有 `@ads` 变体，**没有** `@cn`
- `lyc8503/sing-box-rules@rule-set-geosite`：1892 个，同样没有
- `MetaCubeX/meta-rules-dat@sing`：3792 个，也没有
- `DustinWin/ruleset_geodata`：命名体系完全不同

原因是 v2fly domain-list-community 里 `geolocation-!cn` 和 `cn` 本身是「地理归属」列表，
不带 `@cn` / `@!cn` 属性标签 —— 属性标签挂在 `category-companies` 这一族上。
所以这两个 tag 的正确对应物是：

- `海外公司-大陆服务-域名` → `geosite-category-companies@cn`（6969B，实测 200）
- `大陆相关-海外服务-域名` → `geosite-category-companies@!cn`（200B，实测 200）

### 3. `fc70::/10` 是笔误，且 `ip_is_private` 会吃掉 FakeIP 的 v6 池

原配置的保留地址直连规则：

```yaml
ip_cidr: [0.0.0.0/8, 127.0.0.0/8, 192.168.0.0/16, ::/128, ::1/128, fc70::/10, fe80::/10]
```

`fc70::/10` 不是任何标准保留段（ULA 是 `fc00::/7`），写了等于没写。
但直接改成 `fc00::/7` 或改用 `ip_is_private: true` 会踩另一个坑：

`ip_is_private` 的实现是 `!N.IsPublicAddr(addr)`，而
`IsPublicAddr = !(IsPrivate || IsLoopback || IsMulticast || IsLinkLocalUnicast || ...)`。
Go 的 `Addr.IsPrivate()` 对 v6 判定的是 `fc00::/7` —— 而本配置 FakeIP 的 v6 池是
`dns.fakeip.inet6_range: fc00::/18`，**正好落在里面**。

一旦启用，FakeIP 模式下没命中任何域名规则的 v6 连接，会在 IP 阶段被判成「局域网」直接走
`本机直连` —— 表现是部分网站 IPv6 走漏、且没有任何报错。

改法：v6 侧只写 `fd00::/8`（真实在用的 ULA 前缀），避开 `fc00::/8`。
同时补上原版漏掉的 `10.0.0.0/8`、`172.16.0.0/12`、`100.64.0.0/10`（运营商 CGNAT）、
`169.254.0.0/16`、`224.0.0.0/4`、`255.255.255.255/32`、`ff00::/8`。

### 4. 三个本地 srs 文件白占位置

`哔哩哔哩-域名.srs`、`哔哩哔哩2-域名.srs`、`哔哩哔哩-PCDN｜MCDN-域名.srs`
在 `RuleProviders/` 里躺着，但 `route.rule_set` 里根本没声明 —— 加载不了，也没规则引用。
`虎牙-PCDN｜MCDN-域名` 有声明有使用，但同族的哔哩哔哩 PCDN 就是漏了。

### 5. `mixed` 入站 `listen: '::'` 且无认证

`listen: '::'` + 无 `users` = 同一 Wi-Fi 下任何设备都能免密码把你当代理跳板。
在公共 Wi-Fi 或不可信的家庭网络里这是实打实的开放代理。
我没有擅自改掉（有人确实靠这个给电视盒子用），但在 `notice` 里写清了三种处置方式。

### 6. tun 没有任何 route 排除，局域网发现协议全被黑洞

原 tun 配置只有 `strict_route: true` + `auto_route: true`。
`strict_route` 在 Linux 的语义是「Route all connections to tun」——
mDNS(5353)、SSDP(1900)、NDP、DHCP 这些走组播/链路本地地址的包全被吸进 tun，
而 sing-box 对组播地址没有处理路径，结果就是投屏、AirPlay、DLNA、打印机发现全部失效。

### 7. HTTPDNS 只拦了自维护的一个小 srs

原本只有本地 `HTTPDNS-域名.srs`（解压后 480B，十来个域名）。
`geosite-category-httpdns-cn` 有 100 条，覆盖阿里/百度/华为/腾讯的 HTTPDNS 端点。
HTTPDNS 不拦干净，App 会绕过你所有 DNS 规则直接拿到真实 IP，分流形同虚设。

### 8. `route.ip_rules` 不能用（模块 bug，仅作提醒）

`bundle` 的 `n4()` 里写的是：

```js
Array.isArray(h.route.ip_rules) ? h.route.rules = h.route.ip_rules.filter(...) : ...
```

赋给了 `h.route.rules`（而非 `ip_rules`）。一旦你在 baseConfig 里写了 `route.ip_rules`，
原有的 `route.rules` 会被整体覆盖丢失。别用这个字段。

---

## 二、改了什么

### 规则提供者：18 → 38

**修 URL（5 个）**

全部换到 `lyc8503/sing-box-rules`。选它的理由：
它是 SagerNet 官方 `sing-geosite` 的镜像 + 增量（1892 vs 官方 1873 个 srs，多出 `apple-cn`
`google-cn` 等便利集合），且 geoip/geosite 双分支齐全（官方 `sing-geoip` 只有国家码，
没有 `private`）。实测最后提交时间与官方仓库同日，日更正常。

**新增 20 个规则集**

| 用途 | tag | 源 |
|---|---|---|
| 局域网直连 | `私有网络-域名` / `私有网络-IP` | geosite-private / geoip-private |
| 路由后台 | `路由后台-域名` | 本地自维护 JSON（新建） |
| 时间同步 | `NTP-域名` | geosite-category-ntp（157 条） |
| HTTPDNS 扩展 | `HTTPDNS-大陆-域名` | geosite-category-httpdns-cn（100 条） |
| 大厂大陆分站 | `谷歌/微软/亚马逊-大陆服务-域名` | geosite-{google,microsoft,amazon}@cn |
| 大厂海外分站 | `腾讯/阿里巴巴/字节跳动/哔哩哔哩-海外服务-域名` | geosite-{tencent,alibaba,bytedance,bilibili}@!cn |
| 海外 CDN 国内节点 | `海外CDN-大陆服务-域名` | geosite-category-cdn-!cn@cn |
| 游戏平台国服 | `游戏平台-大陆服务-域名` | geosite-category-games@cn |
| AI 服务 | `AI服务-域名` | geosite-category-ai-!cn |
| IP 归属检测 | `IP归属检测-域名` | geosite-category-ip-geo-detect |
| BT tracker | `BT跟踪器-域名` | geosite-category-public-tracker（默认关） |
| 补声明 | `哔哩哔哩-域名` / `哔哩哔哩2-域名` / `哔哩哔哩-PCDN｜MCDN-域名` | 原有本地 srs |

`update_interval` 按变动频率分档：日更集合 `24h`，`private`/`ntp`/`httpdns`/`games@cn`
这类半年不变的用 `168h`（一周），少 26 次无谓的 GitHub 请求/天。

**扩充 4 个本地 JSON**

- `推送服务-域名`：4 条 → 27 条。补齐国内厂商推送通道（小米 mipush、华为 push.hicloud、
  OPPO/vivo/魅族、极光 jpush、个推 getui、友盟、腾讯 tpns）+ Apple courier 编号域名正则。
  推送通道走错出口 = 消息延迟或收不到，这个表越全越好
- `强制直连-域名`：9 条 → 33 条。补 `.gov.cn` / `.edu.cn` / 六大行 / 12306 / 支付宝 /
  云闪付 / 运营商营业厅。这些走代理常触发风控
- `强制代理-域名`：3 条 → 31 条。补 AI（openai/claude/gemini）+ 开发者基础设施
  （npm/pypi/crates/maven/docker/ghcr/vscode）。国内直连这些不是慢就是断
- `跳过覆写`：7 条 → 32 条。补 IoT（米家/涂鸦/Aqara/石头/科沃斯/Yeelight/博联）+
  游戏平台 + Sonos/Spotify。这些设备的 SNI 与真实目标不一致，嗅探覆写会直接连不上
- `路由后台-域名`（新建，48 条）：小米/TP-Link/华硕/网件/中兴/华为随身 Wi-Fi 的后台域名 +
  OpenWrt/iStoreOS/群晖 + 各家 Clash 面板域名

### 路由

新增 4 条规则、改写 1 条、补 4 个 `enabled: false` 的开关位：

1. **HTTPDNS/PCDN 拦截扩容** — 加入 `HTTPDNS-大陆-域名` 和 `哔哩哔哩-PCDN｜MCDN-域名`
2. **stun 拦截加哔哩哔哩** — 原来只有字节/tiktok/虎牙/斗鱼
3. **新增：路由后台 + 私有网络恒直连** — 用 `type: logical` + `mode: or` 合并两个规则集，
   位置在所有 `clash_mode` 规则之前，保证任何模式下路由后台都能开
4. **新增：NTP 走直连** — 时间偏移会导致 TLS 证书校验失败，这条优先级要高
5. **重写保留地址规则** — 见上文第 3 点，从 7 个 CIDR 扩到 13 个，去掉 `fc70::/10` 笔误，
   v6 侧只用 `fd00::/8` 避开 FakeIP 池
6. **新增开关：`protocol: bittorrent`（默认关）** — 内核确实支持这个嗅探值
   （二进制里有 `ProtocolBitTorrent = "bittorrent"` 常量和 BitTorrent 嗅探器）
7. **新增开关：BT tracker 域名拦截（默认关）** — 与上一条配套
8. **新增开关：国内 QUIC 拦截（默认关）** — 这条是针对「大厂羊毛」出站的：
   `type: http` 只承载 TCP，选它做国内出口时所有 UDP/QUIC 直接黑洞，
   表现为 B 站/微博一直转圈。打开这条把国内 QUIC 拦掉，客户端会自动回落 TCP
9. **代理侧规则集扩容** — 海外分站集合（腾讯/阿里/字节/B站海外）进 `国外出口`；
   大陆分站集合（谷歌/微软/亚马逊/CDN/游戏）进 `本机直连` 或 `国内出口`

### DNS

1. **HTTPDNS 空解析扩容** — 同步 route 侧
2. **新增：内网后缀 → 网关 DNS** — 用 `domain_suffix` 精确匹配
   `.lan/.local/.home/.home.arpa/.internal/.localdomain/.arpa`，交给 `router-dns`。
   注意：`路由后台-域名` 里的 `miwifi.com` `tplogin.cn` `asusrouter.com` 是**真实公网域名**，
   不能丢给网关解析（网关自己也解析不出来），所以它们走 `direct-dns`，
   解析出的内网 IP 再由 route 侧的保留地址规则送去直连
3. **新增：NTP → direct-dns，`rewrite_ttl: 30`** — 必须拿真实 IP，不能进 fakeip
4. **fallback_rules 里补 `私有网络-IP`** — 原来只有 `推送服务-IP` + `大陆相关-IP`
5. **`fakeip.exclude_rule` 补内网后缀** — 双重保险，避免内网域名被 fakeip 化

### 入站

三个入站的 `sniff_override_rules` 统一补上 `路由后台-域名` + `私有网络-域名`
（原来只排除 `跳过覆写` + 推送服务）。嗅探覆写把路由后台的目标改写成域名后，
路由匹配会走岔路。

tun 新增：

```yaml
route_exclude_address:
  - 169.254.0.0/16    # 链路本地（DHCP 前、APIPA）
  - 224.0.0.0/4       # 组播：mDNS 224.0.0.251、SSDP 239.255.255.250
  - 255.255.255.255/32
  - fe80::/10         # v6 链路本地（NDP、mDNS v6）
  - ff00::/8          # v6 组播
```

**刻意不排 `192.168.0.0/16` 和 `10.0.0.0/8`** —— 这是个容易踩反的地方：
网关 DNS（`192.168.1.1:53`）必须继续进 tun，才能被 route 第一条规则劫持到 `域名解析` 出站。
把 `192.168.0.0/16` 加进 `route_exclude_address` 会让 DNS 查询绕过 tun 直达网关，
FakeIP 和全部 DNS 分流整体失效。局域网单播流量由 route 侧的「保留地址直连」处理，
效果一样但不牺牲 DNS 劫持。

我也评估过 1.10 的 `route_exclude_address_set`（可以直接喂 `geoip-cn` 这种规则集），
但它要求 `auto_redirect` + nftables，且与 `route.default_mark: 2333` 冲突
（文档明确写 "Conflict with route.default_mark"），本模块又依赖 default_mark 做 tproxy 兼容，
所以用不了。

### 出站：新增 `国内UDP出口` 与 TCP/UDP 分离

针对上文「一、0」那个问题。新增一个出站：

```yaml
- tag: 国内UDP出口
  type: selector
  interrupt_exist_connections: true
  outbounds: 本机直连          # 兜底，不免流但保证可用
```

然后把免流模式下的国内规则各拆成一对（域名集一对、IP 集一对，共 4 条）：

```yaml
# TCP → 免流出站
- network: tcp
  clash_mode: [规则模式-我要免流-RedirHost, …-FakeIP, …-混合模式]
  rule_set: [推送服务-域名, 强制直连-域名, 大陆相关-域名, …]
  outbound: 国内出口

# 不带 network，承接漏下来的 UDP
- clash_mode: [规则模式-我要免流-RedirHost, …-FakeIP, …-混合模式]
  rule_set: [推送服务-域名, 强制直连-域名, 大陆相关-域名, …]
  outbound: 国内UDP出口
```

顺序很关键：`network: tcp` 那条必须在前。sing-box 按顺序首次匹配，
TCP 命中第一条就不再往下走；UDP 因为 `network` 不匹配而跳过第一条，落到第二条。

几个实现细节：

- **只改「我要免流」分支**。「我不免流」本来就是 `本机直连`（`type: direct`，
  TCP+UDP 都支持），没有这个问题，不需要拆
- **`国内UDP出口` 默认兜底 `本机直连`**，不是留空。`outbound/selector.go:148`
  的行为是 provider 全空时退化到 `OUTBOUNDLESS`，而
  `OUTBOUNDLESS` 在二进制里的实际类型是 `outbound/direct[OUTBOUNDLESS]`（直连）。
  虽然结果一样，但显式写出来用户在面板里能看见、能理解
- **加了 `interrupt_exist_connections: true`**（`国内出口` / `国内UDP出口` 两个）。
  切节点时断开旧连接，避免旧连接还挂在已失效的节点上。
  这个字段两个 fork 内核都支持，`bundle` 的 `lm()` 也不会剥离它
- **没给 `国外出口` / `全局代理` 加这个字段** —— 它们的候选完全由用户在面板里挂，
  保持原样更少意外

验证（脚本模拟按序匹配，代入典型场景）：

```
场景                     规则  出站          结果
微信 收发消息              18   国内出口       OK（TCP 免流）
微信 语音通话(UDP)         19   国内UDP出口    OK（兜底直连）
B站 看视频(TCP)           18   国内出口       OK
B站 看视频(QUIC/UDP)      19   国内UDP出口    OK
手游 长连接(UDP)           19   国内UDP出口    OK
国内站 走IP分流(TCP)       22   国内出口       OK
国内站 走IP分流(UDP)       23   国内UDP出口    OK
```

---

## 三、校验

### 3.1 配置语义：`tools/validate_baseconfig.py`

模拟 `bundle` 生成 `box.json` 的流程再按内核白名单核对。
比 `singBox check` 的优势是不需要 root、不需要真机、能在写配置的当场跑。

```
python3 tools/validate_baseconfig.py sfm/src/baseConfig.yaml tools/kernel_fields.txt
```

检查项：

- `notice` / `enabled` 是否写在 `bundle` 会剥离的位置（写错了就会变成内核的 unknown field）
- 所有键名是否在内核 372 个 JSON tag 白名单里（`tools/kernel_fields.txt` 是从 `singBox` 二进制
  提取的 `json:"xxx"` 全集）
- `rule_set` / `outbound` / `server` / `inbound` / `detour` / `download_detour` / `final`
  的 tag 引用是否都存在，selector 的 `outbounds` 嵌套是否有效
- `rule_set` tag 是否重复、`format` 与 `path` 后缀是否匹配、remote 是否缺 url
- 哪些 `rule_set` 定义了但没人引用（白下载）
- `route.ip_rules` 存在就直接报错（模块 bug）

结果：

```
=== 校验 sfm/src/baseConfig.yaml
rule_set: 38 个, route.rules: 24 条, dns.rules: 22 条, inbounds: 3, outbounds: 8
✅ 无阻断性错误
```

原版跑一遍也是无错（原版的问题是 URL 失效和语义错误，不是语法错误 —— 这也说明为什么
只靠 `singBox check` 发现不了原版的问题）。

另外生成了 `docs/box.preview.json`，是模拟剥离 `notice`/`enabled`、过滤 `enabled: false`
之后的最终产物，可以直接肉眼核对内核会看到什么。启用后的实际规模：
入站 2 个（mixed + tun）、出站 8 个、route.rules 18 条、dns.rules 22 条。

### 3.2 打包完整性：`tools/check_package.py`

**这个是踩了坑之后加的。** 事故经过：

`202608292125` 和 `202608310745` 两个版本的 zip 漏了两个空目录
`sfm/src/log/` 和 `sfm/ProxyProviders/`。原因是 **git 不跟踪空目录** ——
原版这两个目录是空的，`git add` 时没进仓库，CI 的 `zip -r` 自然收不到。

后果分两种，这也是它没被及早发现的原因：

- **覆盖安装完全正常** —— 这两个目录是原版留在 `/data/adb/sfm/` 里的
- **删干净原版全新刷入就起不来**：

```sh
# service.sh:88
mv -f ${LOGDIR}/run.log ${LOGDIR}/run.log.old      # ${LOGDIR} 不存在
nohup node ${DATADIR}/bundle ... 2>${LOGDIR}/run.log &   # 重定向失败
```

node 根本没启动，用户看到的是面板「无法连接神秘后端」。
`bundle` 自身的自检也会抛「日志文件夹缺失」：

```js
// bundle 里的 xh()
if (!existsSync(Hr)) throw "资源文件夹缺失";   // ./src
if (!existsSync(Rc)) throw "日志文件夹缺失";   // ./src/log  ← 死在这
if (!existsSync(Dt)) throw "核心缺失";
if (!existsSync(xr)) throw "核心配置缺失";
```

修法是三层：

1. **`.gitkeep` 占位**（`sfm/src/log/.gitkeep`、`sfm/ProxyProviders/.gitkeep`），
   并把 `.gitignore` 从忽略「目录」改成忽略「目录内容 + 白名单例外」：

   ```gitignore
   sfm/src/log/*
   !sfm/src/log/.gitkeep
   sfm/ProxyProviders/*
   !sfm/ProxyProviders/.gitkeep
   ```

2. **CI 打包前 `mkdir -p` 兜底**，即使 git 里再丢也不会漏

3. **三道校验**：
   - `check_package.py --repo .`：仓库里必需目录/文件齐全、无隐私残留
   - `check_package.py --zip xxx.zip`：打好的包同样检一遍
   - 与 `tools/baseline_paths.txt`（原版 79 个路径的清单，含空目录）逐路径比对，
     再单独 `grep` 断言那两个目录在 zip 里

反向验证过：拿有问题的旧 zip 跑一遍，脚本确实报错：

```
=== 检查 zip m.zip
    文件 68 个，目录 13 个
❌ 错误 2:
  - 缺少目录 sfm/ProxyProviders/
  - 缺少目录 sfm/src/log/
```

还模拟了一遍全新安装（`cp -rf sfm/* → DATADIR` 然后往 `${LOGDIR}` 重定向），
新包成功、旧包失败。

`check_package.py` 顺带检查**不该出现**的东西，防止像社区里某些二改那样
把隐私内容打进包：`sfm/src/appLabels.json`（已装应用列表 = 设备指纹）、
`sfm/src/cache.db`（已选节点缓存）、`sfm/ProxyProviders/*.json`（机场凭据）、
`sfm/src/log/*.log`（运行日志）。

### 3.3 预置规则集：CI 校验格式与完整性

`sfm/RuleProviders/` 里预置了全部 32 个 `.srs`。CI 会检查：

- 每个文件的 magic 是 `SRS` 且 version ∈ {1, 2}（内核只认这两个）
- `baseConfig.yaml` 里每个 `rule_set` 都有对应的落盘文件

第二条是为了避免另一个坑：`type: remote` 的规则集若没有本地文件，
首次启动必须联网下载，而 `route/rule_set_remote.go:96` 的失败是致命的：

```go
if s.lastUpdated.IsZero() {
    err := s.fetchOnce(ctx, startContext)
    if err != nil {
        return E.Cause(err, "initial rule-set: ", s.tag)   // 整个内核起不来
    }
}
```

新用户刚刷完模块还没配节点，`download_detour: 国外出口` 必然拉不动，
27 个远程规则集里任何一个失败都会让内核启动失败。预置 `.srs` 之后
`loadFromFile` 先命中，跳过首次下载，之后照常后台更新。

### notice 能写在哪

`bundle` 的 `$4()` 只在这些位置剥离 `notice`：

```
log / ntp / dns / dns.fakeip / dns.servers[] / dns.rules[]
inbounds[] / outbounds[] / route / route.geoip / route.geosite / route.rules[]
experimental / experimental.clash_api / experimental.v2ray_api(.stats)
```

**`route.rule_set[]` 不在列表里** —— 在规则集条目里写 `notice` 会直接让内核报
`json: unknown field "notice"`，整个配置起不来。同理 `dns.rules[].fallback_rules[]`
和 `route.rules[].rules[]`（logical 子规则）里也不能写。校验器会检出这类错误。

---

## 四、部署

本仓库已经是「配置改好的完整模块」，直接刷 zip 最省事（见 README）。
下面是只覆盖配置的做法，适合已经装了原版、不想重刷模块的情况：

```bash
su

# 必须先停面板 —— baseConfig.yaml 是它的工作缓存，
# 面板每次保存配置都会 writeFileSync + rename 覆盖它
pkill -f 'node /data/adb/sfm/bundle'

# 备份
cp /data/adb/sfm/src/baseConfig.yaml /data/adb/sfm/src/baseConfig.yaml.bak
cp -r /data/adb/sfm/RuleProviders /data/adb/sfm/RuleProviders.bak

# 覆盖
cp sfm/src/baseConfig.yaml /data/adb/sfm/src/
cp sfm/RuleProviders/*.json /data/adb/sfm/RuleProviders/

# 内核自校验（这一步会真的解析 box.json）
/data/adb/sfm/singBox check -D /data/adb/sfm -c box.json

# 重启面板：最省事是 reboot；不想重启就手动拉起（node 来自 termux，环境变量必须带）
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:$PATH
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
nohup node /data/adb/sfm/bundle --enable-source-maps >/dev/null 2>/data/adb/sfm/src/log/run.log &
pidof node && pidof singBox
```

### 覆盖刷入 zip 时的坑

原版 `customize.sh` 检测到 `/data/adb/sfm` 已存在时会走「增量更新」分支，
其中这两行会**把现有配置还原回去**：

```sh
cp -rf ${DATADIR}.old/${TIMESTAMP}/RuleProviders/*.json ${DATADIR}/RuleProviders/
cp -f  ${DATADIR}.old/${TIMESTAMP}/src/baseConfig.yaml  ${DATADIR}/src/baseConfig.yaml
```

这是原作者的设计（保护用户配置不被模块更新覆盖），本仓库没有改动它。
所以在已装原版的机器上刷本 zip，配置还是旧的 —— 需要之后再手动覆盖一次（上面的方式），
或者先卸载原模块再全新刷入。

注意：`baseConfig.yaml` 是面板的**工作缓存**，面板每次改配置都会
`writeFileSync(baseConfig.yaml.new)` 然后 rename 覆盖。所以要在模块服务停止时替换，
否则会被面板写回的内容盖掉。

规则集已全部预置（`sfm/RuleProviders/` 里 32 个 `.srs`），首启不需要联网。
`type: remote` 的规则集会先读 `path` 指向的本地文件
（`route/rule_set_remote.go:89` 的 `loadFromFile`），读到了就跳过首次下载，
之后按 `update_interval` 后台更新。所以没配节点也能启动，
不会因为 `initial rule-set` 失败而卡死。

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

## 五、没做的事

- **没动 `bundle` / `converter`** — 都是 esbuild 压缩产物，`route.ip_rules` 那个 bug
  只能改 JS 修，改了以后模块更新就会覆盖掉，不划算。写进文档提醒别用即可
- **没换 `singBox`** — fork 专有字段（`fallback_rules` / `sniff_override_rules` /
  `providers` 等）在上游 sing-box 里不存在，换官方内核这套配置直接废掉。
  fork 的 `building` 分支本身也停更在 2024-08-15，且其它更新的分支都不带这些字段。
  详细分析见 [KERNEL.md](KERNEL.md)
- **没在真机验证** — 沙盒是 PRoot Alpine，`singBox` 需要 `/system/bin/linker64`，跑不起来；
  `/data/adb` 也不可见。所有结论来自二进制字段提取 + 上游源码比对 + URL 实测，
  内核层面的最终确认要靠你在设备上跑 `singBox check`
- **没自动关掉开放代理** — `mixed` 的 `listen: '::'` 保持原样，只在 `notice` 里说明风险
  和三种改法。这是行为变更，得你自己定
