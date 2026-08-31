#!/usr/bin/env python3
"""校验打包产物的路径完整性。

用途：确保二改 zip 里的路径清单**完全覆盖**原版模块，包括空目录。

背景（真实事故）：
  git 不跟踪空目录，`sfm/ProxyProviders/` 和 `sfm/src/log/` 没进仓库，
  CI 的 `zip -r` 自然收不到。覆盖安装时这两个目录是原版留下的所以看不出问题，
  全新安装就死在 service.sh:88
      mv -f ${LOGDIR}/run.log ${LOGDIR}/run.log.old
  重定向目标目录不存在 → node 根本没启动 → 面板「无法连接神秘后端」。
  bundle 自身的自检也会抛「日志文件夹缺失」。

用法:
    # 对照仓库工作目录
    python3 tools/check_package.py --repo .

    # 对照打好的 zip
    python3 tools/check_package.py --zip SingBox_For_Magisk-tweaked-xxx.zip

    # 与原版 zip 逐路径比对（最严格，需自备原版）
    python3 tools/check_package.py --zip new.zip --baseline 原版.zip
"""
import argparse
import os
import sys
import zipfile

# 刷入后必须存在的目录。空目录也必须在，原因见上。
REQUIRED_DIRS = [
    "sfm",
    "sfm/RuleProviders",
    "sfm/ProxyProviders",      # 出站提供者落盘目录，面板写 ./ProxyProviders/<name>.json
    "sfm/Dashboard",
    "sfm/src",
    "sfm/src/log",             # service.sh 重定向 run.log 到这里；bundle 自检也查它
    "sfm/src/FileProviders",   # 本地订阅 yaml 放这里
    "sfm/src/maho",
    "sfm/src/maho/assets",
    "sfm/src/maho/fonts",
    "webroot",
    "META-INF/com/google/android",
]

# 刷入后必须存在的文件
REQUIRED_FILES = [
    "module.prop",
    "customize.sh",
    "service.sh",
    "post-fs-data.sh",
    "uninstall.sh",
    "handle",
    "keycheck",
    "base.apk",
    "webroot/index.html",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "sfm/singBox",
    "sfm/bundle",
    "sfm/converter",
    "sfm/README.md",
    "sfm/Dashboard/index.html",
    "sfm/src/config.yaml",
    "sfm/src/baseConfig.yaml",
]

# 绝不允许出现在发布包里的东西（隐私 / 运行时残留）
FORBIDDEN = [
    "sfm/src/appLabels.json",     # 已装应用列表 = 设备指纹
    "sfm/src/cache.db",           # 已选节点 / 规则集缓存
    "sfm/src/modulePath",
    "sfm/box.json",
    "box.json",
    "sfm/src/sharedBaseConfig.yaml",
]
FORBIDDEN_PATTERNS = [
    ("sfm/ProxyProviders/", ".json"),   # 真实机场凭据
    ("sfm/src/log/", ".log"),           # 运行日志
]


def from_zip(path):
    """返回 (文件集合, 目录集合)"""
    files, dirs = set(), set()
    with zipfile.ZipFile(path) as z:
        for n in z.namelist():
            if n.endswith("/"):
                dirs.add(n.rstrip("/"))
            else:
                files.add(n)
                # zip 里可能没有显式目录条目，从文件路径补推
                p = os.path.dirname(n)
                while p:
                    dirs.add(p)
                    p = os.path.dirname(p)
    return files, dirs


def from_repo(root):
    files, dirs = set(), set()
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in (".git", "__pycache__")]
        rel = os.path.relpath(dp, root).replace(os.sep, "/")
        if rel == ".":
            rel = ""
        if rel and not rel.startswith((".github", "tools", "docs")):
            dirs.add(rel)
        for f in fn:
            r = f"{rel}/{f}" if rel else f
            files.add(r)
    return files, dirs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip")
    ap.add_argument("--repo")
    ap.add_argument("--baseline", help="原版 zip，逐路径比对（可选）")
    args = ap.parse_args()

    if args.zip:
        files, dirs = from_zip(args.zip)
        src = f"zip {args.zip}"
    elif args.repo:
        files, dirs = from_repo(args.repo)
        src = f"repo {args.repo}"
    else:
        ap.error("需要 --zip 或 --repo")

    print(f"=== 检查 {src}")
    print(f"    文件 {len(files)} 个，目录 {len(dirs)} 个")
    print()

    errors = []

    # 1. 必需目录
    for d in REQUIRED_DIRS:
        if d not in dirs:
            errors.append(f"缺少目录 {d}/")
    # 2. 必需文件
    for f in REQUIRED_FILES:
        if f not in files:
            errors.append(f"缺少文件 {f}")
    # 3. 禁止项
    for f in FORBIDDEN:
        if f in files:
            errors.append(f"不该出现 {f}（隐私 / 运行时残留）")
    for prefix, suffix in FORBIDDEN_PATTERNS:
        for f in files:
            if f.startswith(prefix) and f.endswith(suffix):
                errors.append(f"不该出现 {f}（隐私 / 运行时残留）")

    # 4. 与原版逐路径比对
    if args.baseline:
        bf, bd = from_zip(args.baseline)
        print(f"--- 对照原版 {args.baseline}（文件 {len(bf)}，目录 {len(bd)}）")
        miss_f = sorted(bf - files)
        miss_d = sorted(bd - dirs)
        for d in miss_d:
            errors.append(f"原版有此目录、本包缺失: {d}/")
        for f in miss_f:
            errors.append(f"原版有此文件、本包缺失: {f}")
        extra = sorted(files - bf)
        if extra:
            print("    本包新增（预期内）:")
            for e in extra:
                print("      +", e)
        print()

    if errors:
        print(f"❌ 错误 {len(errors)}:")
        for e in errors:
            print("  -", e)
        return 1

    print("✅ 打包路径完整，无禁止项")
    return 0


if __name__ == "__main__":
    sys.exit(main())
