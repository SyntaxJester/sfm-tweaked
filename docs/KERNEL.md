# 内核为什么不能更新

一句话：**不用更新，而且换不了。** 这套配置绑死在 PuerNya fork 的专有字段上，
官方 sing-box 从 1.11 起改了配置语法，换过去等于重写整份配置。

---

## 现状对照

| | 版本 | 日期 |
|---|---|---|
| 本模块内核 | PuerNya fork `building` 分支 HEAD `067c81a7`，基线 `1.10.0-alpha.29` | 2024-08-15 |
| fork 最后更新 | `building` 分支就停在上面那个 commit | 2024-08-15（约两年前） |
| 官方最新正式 | `v1.13.20` | 2026-08-29 |
| 官方最新预发布 | `v1.14.0-rc.4` | 2026-08-29 |

fork 的其它 32 个分支我都扫过了 —— `dev-next`（2026-01-12）、`respond-fix`（2026-04-16）
这些确实比 `building` 新，但**没有一个带模块需要的专有字段**。

原因是 fork 的组织方式：每个专有功能一个 feature 分支
（`sniff-override-rules`、`outbound-providers`、`dns-fallback`……），
`building` 是把它们全部合起来用于出包的分支。其它分支只是跟着上游走，
所以越新的分支反而越不能用。

`building` 分支上模块必需的四个字段（`fallback_rules` / `sniff_override_rules` /
`outbound_providers` / `use_all_providers`）全部具备，是唯一可用的分支。

---

## 换官方内核要改多少

官方从 1.11 起做了两轮配置结构重构，直接统计本配置受影响的地方：

```
  22 处   route.rules 用 outbound 字段     → 1.11 起改为 action: route + outbound
  29 处   dns.rules 用 server 字段         → 1.12 起改为 action + server
   9 处   dns.servers 用 address 字段      → 1.12 起重构为 type + server 结构
   2 处   block / dns 类型出站             → 1.11 起改为 action: reject / hijack-dns
------
  62 处 结构性改写
```

这只是"语法翻译"的部分。真正没法翻译的是 fork 专有字段，官方内核里**根本不存在**：

```
   4 处   fallback_rules          DNS 解析结果的多级回退
   3 处   accept_result           命中 IP 规则集就采纳上游结果
   3 处   sniff_override_rules    按规则集决定是否用嗅探结果覆写目标
   2 处   allow_fallthrough       允许穿透到下一条 DNS 规则
   2 处   match_all               fallback 兜底匹配
   1 处   providers / outbound_providers   订阅即出站组
   1 处   fake_ip                 匹配 FakeIP 原始目标
   1 处   exclude_rule            fakeip 排除规则
   1 处   lazy_cache / mapping_override / concurrent_dial   DNS 与拨号行为
------
  21 处 专有字段，写进官方内核会直接 unknown field 启动失败
```

（内核用 `DisallowUnknownFields` 解析 `box.json`，多一个键就整体起不来。）

更要紧的是 `bundle`（面板）本身也不认新语法 —— 我搜过它的代码，
`action` / `route_options` / `domain_resolver` / `endpoints` 这些 1.11+ 的概念
零命中，出站类型白名单里也没有 `anytls` / `tailscale`。
面板生成 `box.json` 的整套流水线是按 1.10 的 schema 写的，
换内核就得连面板一起改，而 `bundle` 是 esbuild 压缩产物。

所以「换官方内核」实际是：重写配置 + 改压缩后的 JS 面板 + 放弃 FakeIP 多级回退和
订阅即出站组这些功能。不如直接换个别的模块。

---

## 那停在 2024 年的内核有风险吗

查过了，暂时没有需要紧急处理的：

**已知 CVE**：sing-box 目前唯一的公开安全公告是
[CVE-2023-43644](https://github.com/SagerNet/sing-box/security/advisories)
（SOCKS 入站认证绕过，critical），影响 `< 1.5.0-rc.5`。
本内核基线 `1.10.0-alpha.29` 远在修复版本之后，不受影响。

**编译工具链**：内核用 `go1.23.0`（2024-08）编译，官方 1.13.x 已要求 `go1.24.7`。
Go 自身后续的运行时/标准库修复不会自动进到这个二进制里。
这是慢性的、不是即刻可利用的问题。

**真实风险点不在内核版本上**，而在配置：`mixed` 入站
`listen: '::'` 且无 `users`，同一 Wi-Fi 下任何设备都能免密码当跳板。
这个改一行就能解决，见 README 的安全提示。

---

## 那还能做什么

内核动不了，但配置层的维护是有意义的 —— 这个仓库做的就是这件事：

- 规则源会失效（`UptonEdward/sing-geosite` 已经整个消失），CI 每次改动都会探测 27 个远程源
- 规则集内容日更，`update_interval` 到点自动拉新
- 分流逻辑的 bug 可以修（本仓库修了 `fc70::/10` 笔误和 `ip_is_private` 与 FakeIP v6 池重叠）

**如果你确实需要官方新特性**（AnyTLS、Tailscale endpoint、`domain_resolver`、
kTLS、ICMP 代理这些），正确做法是换一个跟得上上游的客户端 ——
[sing-box-for-android](https://github.com/SagerNet/sing-box-for-android) 官方版、
或 Box for Magisk 之类跟随官方 schema 的模块。
在这个模块上折腾内核版本是走不通的方向。

---

## 我是怎么查的（方法留档）

想自己复核结论，不用真机：

```bash
# 1. 内核的实际 commit
strings -n 6 sfm/singBox | grep -oE '1\.[0-9]+\.[0-9]+-alpha\.[0-9]+-[0-9a-f]{8}'
#    → 1.10.0-alpha.29-067c81a7

# 2. 这个 commit 在哪个分支
curl -s https://api.github.com/repos/PuerNya/sing-box/branches/building \
  | grep -o '"sha": "067c81a7[^"]*"'

# 3. 内核认识哪些字段（372 个）
strings -n 6 sfm/singBox | grep -oE 'json:"[a-zA-Z0-9_,-]+"' \
  | sed 's/json:"//; s/"$//' | tr ',' '\n' \
  | grep -vE '^(omitempty|-)$' | sort -u

# 4. 官方某版本认识哪些（对比 option/ 目录）
curl -s https://raw.githubusercontent.com/SagerNet/sing-box/v1.13.20/option/rule.go \
  | grep 'json:"'
```

`tools/kernel_fields.txt` 就是第 3 步的产物，`tools/validate_baseconfig.py`
用它做白名单校验。
