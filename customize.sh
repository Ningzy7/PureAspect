#!/system/bin/sh
#===========================================================
# Game Aspect Ratio Fix - customize.sh
# 安装时设置脚本权限
#===========================================================

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/game_aspect_fix_daemon.sh 0 0 0755
set_perm $MODPATH/game_list.conf 0 0 0644

ui_print "========================================"
ui_print "  Game Aspect Ratio Fix v1.0"
ui_print "========================================"
ui_print ""
ui_print "  安装完成！"
ui_print "  请在安装后编辑以下文件添加你的游戏包名："
ui_print "  /data/adb/modules/game_aspect_fix/game_list.conf"
ui_print ""
ui_print "  示例："
ui_print "    TARGET_PKGS=("
ui_print "      \"com.tencent.tmgp.sgame\""
ui_print "      \"com.miHoYo.Yuanshen\""
ui_print "    )"
ui_print ""
ui_print "  重启后自动生效"
ui_print "========================================"
