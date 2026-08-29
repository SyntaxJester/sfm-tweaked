# 使用说明

## 从这里开始

- 刷入模块
- 重启
- 访问自动安装的神秘 app，输入初始密码 `node` 获取神秘的力量

## 出现问题检查步骤

- 检查 node 进程是否存在，命令

```shell
su
pidof node
```

- 检查 singBox 进程是否存在，命令

```shell
su
pidof singBox
```

- 查看神秘面板最下方的 log，并根据提示进行对应文件修复
- 使用

```shell
su
/data/adb/sfm/singBox check -D /data/adb/sfm -c box.json
```

命令检查配置文件有无出错并对着修改

- 使用

```shell
su
/data/adb/sfm/singBox run -D /data/adb/sfm -c box.json
```

命令检查是否存在某些运行时的错误

## 热点相关

神秘面板打开热点模式及兼容模式
