#!/system/bin/sh
#===========================================================
# Game Aspect Ratio Fix - Magisk service.sh
# 系统启动后自动启动游戏比例修复守护进程
#===========================================================

MODDIR=${0%/*}

# 等待系统完全启动
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 5
done

# 等待可用的显示环境
while ! wm size >/dev/null 2>&1; do
  sleep 3
done

# 以后台方式启动守护进程
nohup sh "$MODDIR/game_aspect_fix_daemon.sh" > /dev/null 2>&1 &

# 记录启动日志
log -t GAFix "Game Aspect Ratio Fix 守护进程已启动"
