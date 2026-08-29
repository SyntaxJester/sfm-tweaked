#!/bin/sh
DATADIR="/data/adb/sfm"
LOGDIR="${DATADIR}/src/log"
PACKAGELIST="/data/system/packages.list"
TERMUXPKGNAME="com.termux"
WORKDIR=$(cd $(dirname $0); pwd)
RAWCONTENT="借助魔法的力量使用 sing-box 进行代理"

link_ip_forward() {
  while [[ ! -f /data/misc/net/rt_tables ]]; do
      sleep 5
  done

  echo 1 > /proc/sys/net/ipv4/ip_forward
  echo 0 > /dev/ip_forward_stub
  chown $(stat -c '%u:%g' /data/misc/net/rt_tables) /dev/ip_forward_stub
  chcon $(stat -Z -c '%C' /data/misc/net/rt_tables) /dev/ip_forward_stub
  mount -o bind /dev/ip_forward_stub /proc/sys/net/ipv4/ip_forward
}

wait_until_login()
{
  # in case of /data encryption is disabled
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
  done

  sleep 5

  # we doesn't have the permission to rw "/sdcard" before the user unlocks the screen
  local test_file="/sdcard/Android/.CFMTEST"

  true >"$test_file"

  while [ ! -f "$test_file" ]; do
    true >"$test_file"
    sleep 1
  done

  rm "$test_file"
}

install_app()
{
  if [ -f "${WORKDIR}/install" ] ; then
    rm -rf "${WORKDIR}/install"
  elif [ -f "${WORKDIR}/base.apk" ] ; then
    pm install ${WORKDIR}/base.apk
    rm -rf ${WORKDIR}/base.apk
  fi
}

if [ -f "${WORKDIR}/start" ] ; then
  rm -rf ${WORKDIR}/start
  link_ip_forward
  wait_until_login
  install_app
fi

if [ "$(cat ${PACKAGELIST} | grep ${TERMUXPKGNAME})" = "" ] ; then
  sed -i "6cdescription=[缺少 termux]${RAWCONTENT}" ${WORKDIR}/module.prop
  exit 1
fi

export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:$PATH
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib

if [ "$(dpkg -l | grep ^ii | grep nodejs)" == "" ] ; then
  sed -i "6cdescription=[缺少 node]${RAWCONTENT}" ${WORKDIR}/module.prop
  exit 1
elif [ "$(dpkg -l | grep ^ii | grep aapt)" == "" ] ; then
  sed -i "6cdescription=[缺少 aapt]${RAWCONTENT}" ${WORKDIR}/module.prop
  exit 1
fi

NODESTATUS=$(node -v >/dev/null 2>&1; echo $?)
AAPTSTATUS=$(aapt v >/dev/null 2>&1; echo $?)

if [ "${NODESTATUS}" != "" ] && [ "${NODESTATUS}" != "0" ] ; then
  sed -i "6cdescription=[node 环境损坏]${RAWCONTENT}" ${WORKDIR}/module.prop
  exit 1
elif [ "${AAPTSTATUS}" != "" ] && [ "${AAPTSTATUS}" != "0" ] ; then
  sed -i "6cdescription=[aapt 环境损坏]${RAWCONTENT}" ${WORKDIR}/module.prop
  exit 1
fi

sed -i "6cdescription=[环境正常]${RAWCONTENT}" ${WORKDIR}/module.prop
mv -f ${LOGDIR}/run.log ${LOGDIR}/run.log.old
nohup node ${DATADIR}/bundle --enable-source-maps >/dev/null 2>${LOGDIR}/run.log &