# 原作者文件校验清单

`UPSTREAM_SHA256.txt` 列出本仓库中**未作任何修改**的 58 个文件的 sha256，
它们与 `SingBox_For_Magisk` v202408160739 原版逐字节一致。

原模块作者：Puer_Nya — https://github.com/PuerNya

## 校验

在仓库根目录（或解开的 zip 里）执行：

```bash
sha256sum -c UPSTREAM_SHA256.txt
```

全部输出 `OK` 即说明这些文件没被动过。只看失败项：

```bash
sha256sum -c UPSTREAM_SHA256.txt 2>&1 | grep -v ': OK$'
```

（清单里刻意不含注释行 —— BusyBox 的 `sha256sum -c` 不会跳过 `#` 开头的行，
会把它们当成文件名报错。）

## 清单里没有的文件

这些是本仓库的二改内容，不在校验范围内：

```
sfm/src/baseConfig.yaml
sfm/RuleProviders/路由后台-域名.json      （新建）
sfm/RuleProviders/推送服务-域名.json
sfm/RuleProviders/强制直连-域名.json
sfm/RuleProviders/强制代理-域名.json
sfm/RuleProviders/跳过覆写.json
module.prop                              （version / versionCode / name / author）

sfm/RuleProviders/ 里另外 16 个 .srs        （二改新增的预置规则集）
sfm/src/log/.gitkeep                      （占位，git 不跟踪空目录）
sfm/ProxyProviders/.gitkeep               （同上）
```

原版自带的 16 个 `.srs` 仍在校验清单里，可以确认没被改过。

外加不参与刷入的 `tools/`、`docs/`、`.github/`、`README.md`、`CREDITS.md`、
`LICENSE`、`UPSTREAM_SHA256.txt`、`.gitignore`。

改动详情见 [CREDITS.md](../CREDITS.md) 和 [CHANGES.md](CHANGES.md)。

## 和原版 zip 对比

如果你手上有原版 zip，最省事的是用打包校验器逐路径比对：

```bash
python3 tools/check_package.py --zip 二改.zip --baseline 原版.zip
```

它会列出「原版有、本包缺失」和「本包新增」两类差异，
并额外检查必需目录、必需文件、以及不该出现的隐私残留。

也可以手动比 sha256：

```bash
mkdir /tmp/orig && cd /tmp/orig
unzip -q /path/to/原版.zip
find . -type f -exec sha256sum {} + | sed 's|\./||' | sort -k2 > /tmp/a.txt

cd /path/to/sfm-tweaked
sort -k2 UPSTREAM_SHA256.txt > /tmp/b.txt

# 只应该差那 7 个二改文件
diff /tmp/a.txt /tmp/b.txt
```

## 版本对照

| | 原版 | 本仓库 |
|---|---|---|
| `version` | `202408160739` | `202608312000` |
| `versionCode` | `8` | `11` |
| `id` | `SingBox_For_Magisk` | 不变 |
| `description` | 借助魔法的力量使用 sing-box 进行代理 | 不变 |

`id` 不变是为了让 `/data/adb/sfm` 的增量更新逻辑继续生效；
`description` 不变是因为 `service.sh` 会用 `sed -i "6c..."` 按行号改写它。
