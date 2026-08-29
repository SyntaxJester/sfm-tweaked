#!/usr/bin/env python3
"""
sfm baseConfig.yaml 静态校验器

模拟 SingBox_For_Magisk 的 bundle(converter) 生成 box.json 的流程，
然后按 sing-box 内核（DisallowUnknownFields）的字段白名单逐项核对。

用法: python3 validate_baseconfig.py <baseConfig.yaml> [--tags <字段白名单文件>]
"""
import sys
import copy
import yaml

# ---- 内核字段白名单（从 singBox 二进制的 json tag 提取） ----
KERNEL_FIELDS = set()

# converter 会剥离 notice 的位置（$4 函数）
NOTICE_STRIPPED = {
    "log", "ntp", "dns", "dns.fakeip", "dns.servers[]", "dns.rules[]",
    "inbounds[]", "outbounds[]", "route", "route.geoip", "route.geosite",
    "route.rules[]", "experimental", "experimental.clash_api",
    "experimental.v2ray_api", "experimental.v2ray_api.stats",
}
# converter 会剥离 enabled 的位置（n4 函数）
ENABLED_STRIPPED = {
    "dns.servers[]", "dns.rules[]", "dns.rules[].rules[]",
    "route.rules[]", "route.rules[].rules[]",
    "inbounds[]", "outbounds[]", "outbound_providers[]",
}
# 内核本身接受 enabled 的位置（不需要 converter 剥离）
ENABLED_NATIVE = {
    "dns.fakeip", "ntp", "experimental.cache_file", "experimental.clash_api",
    "experimental.v2ray_api", "experimental.v2ray_api.stats",
    "packages_list",
}
# 值为自由 map、键不是字段名的位置
FREE_MAP_PREFIX = ("dns.hosts", "outbounds.headers", "inbounds.headers",
                   "route.rule_set.headers")

errors = []
warns = []


def err(msg):
    errors.append(msg)


def warn(msg):
    warns.append(msg)


def load_kernel_fields(path):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                KERNEL_FIELDS.add(line)
    # converter 生成的、内核不认但 converter 自己会删掉的键无需列入
    return KERNEL_FIELDS


def check_notice_enabled(cfg):
    """检查 notice / enabled 是否只出现在 converter 会剥离的位置"""
    def walk(node, path):
        if isinstance(node, dict):
            for k in ("notice", "enabled"):
                if k in node:
                    if k == "enabled" and path in ENABLED_NATIVE:
                        continue
                    table = NOTICE_STRIPPED if k == "notice" else ENABLED_STRIPPED
                    if path not in table:
                        err(f"{k} 出现在 converter 不会剥离的位置 {path or '<root>'} "
                            f"→ 会作为未知字段传给内核，导致 box.json 校验失败")
            for k, v in node.items():
                walk(v, f"{path}.{k}" if path else k)
        elif isinstance(node, list):
            for item in node:
                walk(item, f"{path}[]")

    walk(cfg, "")
    # packages_list / outbound_providers 整体被删，其 notice 无害
    global errors
    errors = [e for e in errors if "packages_list" not in e]


def simulate_converter(cfg):
    """粗略模拟 converter：剥离 notice/enabled，删除模块专有顶层键"""
    h = copy.deepcopy(cfg)

    def strip(node, path):
        if isinstance(node, dict):
            if path in NOTICE_STRIPPED:
                node.pop("notice", None)
            if path in ENABLED_STRIPPED:
                node.pop("enabled", None)
            for k, v in list(node.items()):
                strip(v, f"{path}.{k}" if path else k)
        elif isinstance(node, list):
            for item in node:
                strip(item, f"{path}[]")

    strip(h, "")
    h.pop("packages_list", None)
    h.pop("outbound_providers", None)
    h.pop("rule_providers", None)
    return h


def check_unknown_fields(h):
    """对照内核白名单检查所有键名"""
    def walk(node, path):
        if isinstance(node, dict):
            for k, v in node.items():
                # 值为自由 map 的位置，键不是字段名
                if path.startswith(FREE_MAP_PREFIX):
                    continue
                if k not in KERNEL_FIELDS:
                    err(f"内核不认识的字段: {path}.{k}" if path else f"内核不认识的顶层字段: {k}")
                walk(v, f"{path}.{k}" if path else k)
        elif isinstance(node, list):
            for item in node:
                walk(item, path)

    walk(h, "")


def check_references(h):
    """检查 tag 引用完整性"""
    rs_tags = {r["tag"] for r in h.get("route", {}).get("rule_set", [])}
    ob_tags = {o["tag"] for o in h.get("outbounds", [])}
    dns_tags = {s["tag"] for s in h.get("dns", {}).get("servers", [])}
    in_tags = {i["tag"] for i in h.get("inbounds", [])}

    # rule_set 重复
    seen = set()
    for r in h.get("route", {}).get("rule_set", []):
        if r["tag"] in seen:
            err(f"rule_set tag 重复: {r['tag']}")
        seen.add(r["tag"])

    def as_list(v):
        if v is None:
            return []
        return v if isinstance(v, list) else [v]

    def check_rule(rule, ctx, allowed_ob, allowed_dns):
        for t in as_list(rule.get("rule_set")):
            if t not in rs_tags:
                err(f"{ctx}: rule_set 引用了不存在的 tag「{t}」")
        for t in as_list(rule.get("outbound")):
            if t in ("any",) or t == "OUTBOUNDLESS":
                continue
            if allowed_ob and t not in ob_tags:
                err(f"{ctx}: outbound 引用了不存在的出站「{t}」")
        for t in as_list(rule.get("server")):
            if allowed_dns and t not in dns_tags:
                err(f"{ctx}: server 引用了不存在的 DNS 服务器「{t}」")
        for t in as_list(rule.get("inbound")):
            if t not in in_tags:
                err(f"{ctx}: inbound 引用了不存在的入站「{t}」")
        for sub in rule.get("rules", []) or []:
            check_rule(sub, ctx + "/logical", allowed_ob, allowed_dns)
        for sub in rule.get("fallback_rules", []) or []:
            check_rule(sub, ctx + "/fallback", False, True)

    for i, rule in enumerate(h.get("dns", {}).get("rules", [])):
        check_rule(rule, f"dns.rules[{i}]", False, True)
    for i, rule in enumerate(h.get("route", {}).get("rules", [])):
        check_rule(rule, f"route.rules[{i}]", True, False)
    for i, ib in enumerate(h.get("inbounds", [])):
        for j, r in enumerate(ib.get("sniff_override_rules", []) or []):
            check_rule(r, f"inbounds[{i}].sniff_override_rules[{j}]", False, False)

    # DNS server detour 必须是已存在出站
    for s in h.get("dns", {}).get("servers", []):
        d = s.get("detour")
        if d and d not in ob_tags:
            err(f"dns.servers[{s['tag']}].detour 引用了不存在的出站「{d}」")
    # rule_set download_detour
    for r in h.get("route", {}).get("rule_set", []):
        d = r.get("download_detour")
        if d and d not in ob_tags:
            err(f"rule_set[{r['tag']}].download_detour 引用了不存在的出站「{d}」")
    # route.final
    fin = h.get("route", {}).get("final")
    if fin and fin not in ob_tags:
        err(f"route.final 引用了不存在的出站「{fin}」")
    # selector 的 outbounds
    for o in h.get("outbounds", []):
        for t in as_list(o.get("outbounds")):
            if t not in ob_tags:
                err(f"outbounds[{o['tag']}].outbounds 引用了不存在的出站「{t}」")

    # 未被任何规则引用的 rule_set（浪费下载/内存）
    used = set()

    def collect(rule):
        for t in as_list(rule.get("rule_set")):
            used.add(t)
        for sub in (rule.get("rules") or []) + (rule.get("fallback_rules") or []):
            collect(sub)

    for rule in h.get("dns", {}).get("rules", []):
        collect(rule)
    for rule in h.get("route", {}).get("rules", []):
        collect(rule)
    for ib in h.get("inbounds", []):
        for r in ib.get("sniff_override_rules", []) or []:
            collect(r)
    for t in sorted(rs_tags - used):
        warn(f"rule_set「{t}」定义了但没有任何规则引用")


def check_rule_set_entries(cfg):
    """rule_set 条目内不允许出现 notice/enabled（converter 不剥离）"""
    for r in cfg.get("route", {}).get("rule_set", []):
        for k in ("notice", "enabled"):
            if k in r:
                err(f"rule_set[{r.get('tag')}] 含 {k} 字段 → converter 不会剥离，内核会报 unknown field")
        if r.get("type") == "remote":
            for k in ("url", "download_detour", "update_interval"):
                if k not in r:
                    warn(f"rule_set[{r['tag']}] 是 remote 但缺少 {k}")
        if r.get("type") == "local" and "url" in r:
            warn(f"rule_set[{r['tag']}] 是 local 却带 url，url 会被忽略")
        if "format" not in r:
            err(f"rule_set[{r.get('tag')}] 缺少 format")
        elif r["format"] not in ("binary", "source"):
            err(f"rule_set[{r['tag']}].format 非法: {r['format']}")
        path = r.get("path", "")
        if r.get("format") == "binary" and not path.endswith(".srs"):
            warn(f"rule_set[{r['tag']}] format=binary 但 path 不是 .srs：{path}")
        if r.get("format") == "source" and not path.endswith(".json"):
            warn(f"rule_set[{r['tag']}] format=source 但 path 不是 .json：{path}")


def check_ip_rules(cfg):
    if "ip_rules" in cfg.get("route", {}):
        err("route.ip_rules 不可用：bundle 的 n4() 会把 ip_rules 赋值给 route.rules，"
            "导致原有 route.rules 全部丢失（模块 bug）")


def main():
    path = sys.argv[1]
    tags = sys.argv[2] if len(sys.argv) > 2 else "/tmp/tags_all.txt"
    load_kernel_fields(tags)
    with open(path) as f:
        cfg = yaml.safe_load(f)

    check_ip_rules(cfg)
    check_rule_set_entries(cfg)
    check_notice_enabled(cfg)
    h = simulate_converter(cfg)
    check_unknown_fields(h)
    check_references(h)

    print(f"=== 校验 {path}")
    print(f"rule_set: {len(cfg.get('route', {}).get('rule_set', []))} 个, "
          f"route.rules: {len(cfg.get('route', {}).get('rules', []))} 条, "
          f"dns.rules: {len(cfg.get('dns', {}).get('rules', []))} 条, "
          f"inbounds: {len(cfg.get('inbounds', []))}, "
          f"outbounds: {len(cfg.get('outbounds', []))}")
    if errors:
        print(f"\n❌ 错误 {len(errors)}:")
        for e in errors:
            print("  -", e)
    if warns:
        print(f"\n⚠️  提示 {len(warns)}:")
        for w in warns:
            print("  -", w)
    if not errors:
        print("\n✅ 无阻断性错误")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
