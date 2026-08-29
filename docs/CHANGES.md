# sfm 规则提供者 / 路由 / 入站 完善说明

针对 `SingBox_For_Magisk` (`神秘啊神秘` v202408160739) 的配置层改造。
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

---

## 三、校验

写了 `tools/validate_baseconfig.py`，模拟 `bundle` 生成 `box.json` 的流程再按内核白名单核对。
比 `singBox check` 的优势是不需要 root、不需要真机、能在写配置的当场跑。

```
python3 tools/validate_baseconfig.py src/baseConfig.yaml tools/kernel_fields.txt
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
=== 校验 src/baseConfig.yaml
rule_set: 38 个, route.rules: 22 条, dns.rules: 22 条, inbounds: 3, outbounds: 7
✅ 无阻断性错误
```

原版跑一遍也是无错（原版的问题是 URL 失效和语义错误，不是语法错误 —— 这也说明为什么
只靠 `singBox check` 发现不了原版的问题）。

另外生成了 `docs/box.preview.json`，是模拟剥离 `notice`/`enabled`、过滤 `enabled: false`
之后的最终产物，可以直接肉眼核对内核会看到什么。启用后的实际规模：
入站 2 个（mixed + tun）、route.rules 16 条、dns.rules 22 条。

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

```bash
su
# 备份
cp /data/adb/sfm/src/baseConfig.yaml /data/adb/sfm/src/baseConfig.yaml.bak
cp -r /data/adb/sfm/RuleProviders /data/adb/sfm/RuleProviders.bak

# 覆盖
cp src/baseConfig.yaml /data/adb/sfm/src/
cp RuleProviders/*.json /data/adb/sfm/RuleProviders/

# 内核自校验（这一步会真的解析 box.json）
/data/adb/sfm/singBox check -D /data/adb/sfm -c box.json

# 重启模块服务
pkill -f 'node /data/adb/sfm/bundle'
sh /data/adb/sfm/../service.sh   # 或直接重启设备
```

注意：`baseConfig.yaml` 是面板的**工作缓存**，面板每次改配置都会
`writeFileSync(baseConfig.yaml.new)` 然后 rename 覆盖。所以要在模块服务停止时替换，
否则会被面板写回的内容盖掉。

首次启动会下载 26 个远程规则集（合计约 3MB），走 `download_detour: 国外出口` —— 
必须先有一个能用的国外节点，否则 `initial rule-set` 失败、内核起不来。
如果节点还没配好，临时把这些 `rule_set` 的 `type` 改成 `local` 跑起来再说。

### 回滚

```bash
su
cp /data/adb/sfm/src/baseConfig.yaml.bak /data/adb/sfm/src/baseConfig.yaml
rm -rf /data/adb/sfm/RuleProviders && mv /data/adb/sfm/RuleProviders.bak /data/adb/sfm/RuleProviders
rm -f /data/adb/sfm/src/cache.db   # 清掉规则集缓存，避免新旧混用
```

---

## 五、没做的事

- **没动 `bundle` / `converter`** — 都是 esbuild 压缩产物，`route.ip_rules` 那个 bug
  只能改 JS 修，改了以后模块更新就会覆盖掉，不划算。写进文档提醒别用即可
- **没换 `singBox`** — fork 专有字段（`fallback_rules` 等）在上游 sing-box 里不存在，
  换官方内核这套配置直接废掉
- **没在真机验证** — 沙盒是 PRoot Alpine，`singBox` 需要 `/system/bin/linker64`，跑不起来；
  `/data/adb` 也不可见。所有结论来自二进制字段提取 + 上游源码比对 + URL 实测，
  内核层面的最终确认要靠你在设备上跑 `singBox check`
- **没自动关掉开放代理** — `mixed` 的 `listen: '::'` 保持原样，只在 `notice` 里说明风险
  和三种改法。这是行为变更，得你自己定
