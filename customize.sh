SKIPUNZIP=1

if [ "${ARCH}" != "arm64" ] ; then
  abort "- 不支持的架构，本模块只支持 arm64 架构的设备"
fi

unzip -o "${ZIPFILE}" -x 'META-INF/*' -d ${MODPATH} >&2
set_perm_recursive ${MODPATH} 0 0 7777 7777

DATADIR="/data/adb/sfm"
TIMESTAMP=$(date "+%Y%m%d%H%M")
PACKAGELIST="/data/system/packages.list"
TERMUXPKGNAME="com.termux"
BOXPATH="busybox"
FIRSTINSTALL=1

if ![ "${BOOTMODE}" ] ; then
  ui_print "*********************************************************"
  ui_print "! 从 Recovery 安装是不被支持的"
  ui_print "! 请从 Magisk/KernelSU/APatch app 安装"
  abort    "*********************************************************"
fi

if [ "${KSU}" ] ; then
  BOXPATH="/data/adb/ksu/bin/busybox"
  ui_print "- 刷写过程在 KernelSU 环境下运行"
elif [ "${APATCH}" ] ; then
  BOXPATH="/data/adb/ap/bin/busybox"
  ui_print "- 刷写过程在 APatch 环境下运行"
elif [ ${MAGISK_VER_CODE} ] ; then
  BOXPATH="/data/adb/magisk/busybox"
  ui_print "- 刷写过程在 Magisk 环境下运行"
else
  ui_print "*********************************************************"
  ui_print "! 不支持的安装环境，请在 Magisk/KernelSU/APatch 环境下刷写本模块"
  abort    "*********************************************************"
fi

if [ "$(cat ${PACKAGELIST} | grep ${TERMUXPKGNAME})" = "" ] ; then
  ui_print "*********************************************************"
  ui_print "! 检测到未安装 termux app，请安装后再刷写本模块，3s 后为您自动跳转下载页"
  ui_print "*********************************************************"
  sleep 3
  am start -a android.intent.action.VIEW -d "https://f-droid.org/repo/com.termux_118.apk"
  abort
fi

export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:$PATH
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib

if [ $(dpkg -l | grep ^ii | grep nodejs) == "" ] ; then
  ui_print "*********************************************************"
  ui_print "! 检测到未在 termux 中安装 node 环境，请安装后再刷写本模块"
  abort    "*********************************************************"
elif [ $(dpkg -l | grep ^ii | grep aapt) == "" ] ; then
  ui_print "*********************************************************"
  ui_print "! 检测到未在 termux 中安装 aapt 环境，请安装后再刷写本模块"
  abort    "*********************************************************"
fi

NODESTATUS=$(node -v > /dev/null 2>&1; echo $?)
AAPTSTATUS=$(aapt v > /dev/null 2>&1; echo $?)

if [ "${NODESTATUS}" != "" ] && [ "${NODESTATUS}" != "0" ] ; then
  ui_print "*********************************************************"
  ui_print "! node 损坏，请修复后再刷写本模块"
  abort    "*********************************************************"
elif [ "${AAPTSTATUS}" != "" ] && [ "${AAPTSTATUS}" != "0" ] ; then
  ui_print "*********************************************************"
  ui_print "! aapt 损坏，请修复后再刷写本模块"
  abort    "*********************************************************"
fi

DEFAULTSIGNAL=$(${BOXPATH} timeout 0.00001s ${MODPATH}/keycheck; echo $?)
ISOLDUI="0"

install_app()
{
  local maho="webapp.shenmi"

  if ! [ "$(cat ${PACKAGELIST} | grep ${maho})" = "" ] ; then
    if [ "${ISOLDUI}" == "0" ]; then
      return 0
    fi
    ui_print "- 已安装神秘 app，将自动清除 app 缓存"
    pm clear ${maho} >/dev/null
    rm -rf ${MODPATH}/base.apk
    return 0
  fi

readkey_install_app:

  ui_print "***************************************~******************"
  ui_print "- 未安装神秘 app，请根据提示按下相应按键，你将有 10s 的反应时间"
  ui_print "- 音量下/音量 -：安装神秘 app（默认响应）"
  ui_print "- 音量上/音量 +：跳过"
  ui_print "****************************************~*****************"

  local SIGNAL=$(${BOXPATH} timeout 10s ${MODPATH}/keycheck; echo $?)

  if [ "${SIGNAL}" = "42" ] ; then
    ui_print "- 跳过"
    rm -rf ${MODPATH}/base.apk
    return 0
  elif ! [ "${SIGNAL}" = "41" ] && ! [ "${SIGNAL}" = "${DEFAULTSIGNAL}" ] ; then
    ui_print "- 错误按键，请重新按键"
    sleep 1
    goto readkey_install_app
  fi
  
  ui_print "- 安装神秘 app"
  pm install ${MODPATH}/base.apk
  if [ "$(cat ${PACKAGELIST} | grep ${maho})" = "" ] ; then
    ui_print "- 安装失败，将在下次系统启动时自动安装"
  else
    rm -rf ${MODPATH}/base.apk
  fi
}

kill_node()
{
  local nodePid=$(echo "$1" | awk -F' ' '{print $7}' | awk -F'/' '{print $1}' )
  kill -9 ${nodePid}
}

start_maho()
{
  ${MODPATH}/service.sh
  sleep 3
  
  if [ "$(netstat -tunlp | grep 23333 | grep node )" != "" ] ; then
    ui_print "- 神秘后端启动完成，请访问面板/app 获得帮助"
  else
    ui_print "- 神秘后端启动失败，请尝试重启设备或检查日志"
  fi
}

key="node"

if [ -f ${DATADIR}/src/config.yaml ] ; then
  key=$(${BUSYBOX} awk '/authorizationKey/{print $2}' ${DATADIR}/src/config.yaml)
elif [ -f ${DATADIR}/src/config.hjson ] ; then
  key=$(${BUSYBOX} awk '/authorizationKey/{print $2}' ${DATADIR}/src/config.hjson)
fi

start_process()
{
  touch ${MODPATH}/install
  local mahoStatus=$(netstat -tunlp | grep 23333 | grep node )

  if [ "${FIRSTINSTALL}" = "1" ] ; then
    ui_print "- 正在启动神秘后端"
    if [ "${mahoStatus}" != "" ] ; then
      kill_node "${mahoStatus}"
    fi
    return 0
  fi

  if [ "$(ps -el | grep singBox)" = "" ] ; then
    ui_print "- 核心未在运行，将直接更新"
    kill_node
    start_maho
    return 0
  fi

readkey_start_process:

  ui_print "*********************************************************"
  ui_print "- 核心正在运行，请根据提示按下相应按键，你将有 10s 的反应时间"
  ui_print "- 音量下/音量 -：立即更新神秘（默认响应）"
  ui_print "- 音量上/音量 +：下次启动时更新"
  ui_print "*********************************************************"

  local SIGNAL=$(${BOXPATH} timeout 10s ${MODPATH}/keycheck; echo $?)

  if [ "${SIGNAL}" = "42" ] ; then
    ui_print "- 下次启动时更新"
    return 0
  elif ! [ "${SIGNAL}" = "41" ] && ! [ "${SIGNAL}" = "${DEFAULTSIGNAL}" ] ; then
    ui_print "- 错误按键，请重新按键"
    sleep 1
    goto readkey_start_process
  fi

  ui_print "- 立即更新神秘"
  if [ "${mahoStatus}" != "" ] ; then
    curl "127.0.0.1:23333/api/kernel" -H "authorization: ${key}" -H "Content-Type: application/json" -d '{"method":"stop"}' > /dev/null 2>&1
    kill_node "${mahoStatus}"
  else
    killall -9 singBox
  fi

  ui_print "- 已关闭核心和神秘后端，现在开始重新启动"
  start_maho
}

if [ -d ${DATADIR} ] ; then
  ui_print "- 检测到数据目录，开始增量更新"
  FIRSTINSTALL=0
  MODULEPATH=$(cat ${DATADIR}/src/modulePath)
  PROPPATH="${MODULEPATH}/module.prop"
  MODULEVERSION=$(cat ${PROPPATH} | grep versionCode | awk -F= '{print $2}' )

  if [ ${MODULEVERSION} -lt 5 ]; then
    ui_print "*********************************************************"
    ui_print "! 当前模块版本太低，请先升级到 202303042355 再刷写此版本"
    abort    "*********************************************************"
  elif [ ${MODULEVERSION} -lt 8 ]; then
    ISOLDUI="1"
  fi

  mkdir -p ${DATADIR}.old/${TIMESTAMP}/
  mv -f $(ls ${DATADIR} | grep -v "singBox" | awk '{print"/data/adb/sfm/"$0}') ${DATADIR}.old/${TIMESTAMP}/
  mv -f ${MODPATH}/sfm/singBox ${DATADIR}/singBox.new
  cp -rf ${MODPATH}/sfm/* ${DATADIR}/
  cp -rf ${DATADIR}.old/${TIMESTAMP}/box.json ${DATADIR}/box.json
  cp -rf ${DATADIR}.old/${TIMESTAMP}/ProxyProviders/*.json ${DATADIR}/ProxyProviders/
  cp -rf ${DATADIR}.old/${TIMESTAMP}/RuleProviders/*.json ${DATADIR}/RuleProviders/
  cp -rf ${DATADIR}.old/${TIMESTAMP}/RuleProviders/*.srs ${DATADIR}/RuleProviders/
  rm -rf ${DATADIR}/Dashboard/*
  cp -rf ${DATADIR}.old/${TIMESTAMP}/Dashboard/* ${DATADIR}/Dashboard/
  cp -rf ${DATADIR}.old/${TIMESTAMP}/src/FileProviders/* ${DATADIR}/src/FileProviders/
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/geosite.db ${DATADIR}/src/geosite.db
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/geosite.db.new ${DATADIR}/src/geosite.db.new
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/geoip.db ${DATADIR}/src/geoip.db
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/geoip.db.new ${DATADIR}/src/geoip.db.new
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/cache.db ${DATADIR}/src/cache.db
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/config.hjson ${DATADIR}/src/config.hjson
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/baseConfig.hjson ${DATADIR}/src/baseConfig.hjson
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/config.yaml ${DATADIR}/src/config.yaml
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/baseConfig.yaml ${DATADIR}/src/baseConfig.yaml
  cp -f ${DATADIR}.old/${TIMESTAMP}/src/appLabels.json ${DATADIR}/src/appLabels.json
  if [ -f ${DATADIR}/src/baseConfig.hjson ] || [ -f ${DATADIR}/src/config.hjson ] ; then
    node ${DATADIR}/converter
  fi
  rm -rf ${DATADIR}/converter
else
  ui_print "- 未检测到数据目录，开始全量安装"
  mkdir -p ${DATADIR}
  cp -rf ${MODPATH}/sfm/* ${DATADIR}/
fi

if [ ! -f ${DATADIR}/src/appLabels.json ] ; then
  ui_print "- 未检测到应用名缓存，现在开始生成"
  node ${MODPATH}/handle --enable-source-maps
fi

if [ "${KSU}" ] ; then
  ui_print "- KernuelSU 支持模块 webui，跳过检查神秘 app 的安装情况"
  rm -rf ${MODPATH}/base.apk
  touch ${DATADIR}/clear.sh
  echo "sleep 3" > ${DATADIR}/clear.sh
  echo "pm clear me.weishu.kernelsu" >> ${DATADIR}/clear.sh
  echo "rm -rf ${DATADIR}/clear.sh" >> ${DATADIR}/clear.sh
elif [ "${APATCH}" ] ; then
  ui_print "- APatch 支持模块 webui，跳过检查神秘 app 的安装情况"
  rm -rf ${MODPATH}/base.apk
  touch ${DATADIR}/clear.sh
  echo "sleep 3" > ${DATADIR}/clear.sh
  echo "pm clear me.bmax.apatch" >> ${DATADIR}/clear.sh
  echo "rm -rf ${DATADIR}/clear.sh" >> ${DATADIR}/clear.sh
else
  rm -rf ${MODPATH}/webroot
  install_app
fi

ui_print "- 开始设置环境权限"
set_perm_recursive ${DATADIR} 0 0 7777 7777

start_process

ui_print "- 开始清理环境"

rm -rf ${MODPATH}/sfm
rm -rf ${MODPATH}/keycheck
rm -rf ${MODPATH}/handle

if [ "${ISOLDUI}" == "0" ]; then
  return 0
elif [ "${KSU}" ] ; then
  ui_print "- KernuelSU 管理器缓存将在 3s 后被自动清除，如果您使用 KernuelSU 管理器进行模块安装，届时它将会自动退出，是正常现象，请勿惊慌"
  nohup su -c "${DATADIR}/clear.sh" >/dev/null 2>&1 &
elif [ "${APATCH}" ] ; then
  ui_print "- APatch 管理器缓存将在 3s 后被自动清除，如果您使用 APatch 管理器进行模块安装，届时它将会自动退出，是正常现象，请勿惊慌"
  nohup su -c "${DATADIR}/clear.sh" >/dev/null 2>&1 &
fi