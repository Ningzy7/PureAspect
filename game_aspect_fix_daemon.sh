#!/system/bin/sh
#===========================================================
# Game Aspect Ratio Fix - 核心守护脚本
# 检测游戏窗口从小窗→全屏的切换，触发渲染重建
#===========================================================

MODDIR=${0%/*}

# 加载配置
CONFIG="$MODDIR/game_list.conf"
INTERVAL=2
DEBOUNCE=5
STABILIZE_TIME=3  # 游戏启动后等待稳定的秒数

if [ -f "$CONFIG" ]; then
  . "$CONFIG"
fi

if [ ${#TARGET_PKGS[@]} -eq 0 ]; then
  echo "[GAFix] 错误：未配置目标游戏，请编辑 $CONFIG"
  exit 1
fi

# 获取原始分辨率
PHYSICAL_SIZE=""
SIZE_LINE=$(wm size 2>/dev/null | grep 'Physical size:' | head -1)
[ -n "$SIZE_LINE" ] && PHYSICAL_SIZE=$(echo "$SIZE_LINE" | sed 's/.*Physical size: //')

if [ -z "$PHYSICAL_SIZE" ]; then
  SIZE_LINE=$(wm size 2>/dev/null | grep 'Override size:' | head -1)
  [ -n "$SIZE_LINE" ] && PHYSICAL_SIZE=$(echo "$SIZE_LINE" | sed 's/.*Override size: //')
fi

if [ -z "$PHYSICAL_SIZE" ]; then
  echo "[GAFix] 错误：无法获取分辨率"
  exit 1
fi

W=$(echo "$PHYSICAL_SIZE" | cut -dx -f1)
H=$(echo "$PHYSICAL_SIZE" | cut -dx -f2)

log -t GAFix "启动：分辨率=${PHYSICAL_SIZE}, 监控包数=${#TARGET_PKGS[@]}"

# ---- 为每个包维护状态 ----
PKGT_COUNT=${#TARGET_PKGS[@]}
LAST_WAS_SMALL=""
LAST_FULLSCREEN=""
LAST_TRIGGERED=""
START_TIME=""
LAST_ALIVE=""

init_state() {
  local i
  LAST_WAS_SMALL=""
  LAST_FULLSCREEN=""
  LAST_TRIGGERED=""
  START_TIME=""
  LAST_ALIVE=""
  i=0
  while [ $i -lt $PKGT_COUNT ]; do
    LAST_WAS_SMALL="${LAST_WAS_SMALL}:false"
    LAST_FULLSCREEN="${LAST_FULLSCREEN}:false"
    LAST_TRIGGERED="${LAST_TRIGGERED}:0"
    START_TIME="${START_TIME}:0"
    LAST_ALIVE="${LAST_ALIVE}:false"
    i=$((i+1))
  done
}

get_val() {
  local list="$1" idx="$2"
  echo "$list" | cut -d: -f$((idx+2))
}

set_val() {
  local list="$1" idx="$2" val="$3"
  local i=0 result=""
  local old
  while [ $i -lt $PKGT_COUNT ]; do
    old=$(echo "$list" | cut -d: -f$((i+2)))
    if [ "$i" -eq "$idx" ]; then
      result="${result}:${val}"
    else
      result="${result}:${old}"
    fi
    i=$((i+1))
  done
  echo "$result"
}

init_state

# ---- 触发渲染重建 ----
trigger_rebuild() {
  local pkg="$1" pkg_idx="$2"
  local now
  now=$(date +%s)
  local last_trig
  last_trig=$(get_val "$LAST_TRIGGERED" "$pkg_idx")
  local elapsed=$(( now - last_trig ))
  [ "$elapsed" -lt "$DEBOUNCE" ] && return

  log -t GAFix "⚡ [$pkg] 从小窗→全屏，触发渲染重建"
  wm size "$((W-1))x${H}" >/dev/null 2>&1
  sleep 0.15
  wm size reset >/dev/null 2>&1
  
  LAST_TRIGGERED=$(set_val "$LAST_TRIGGERED" "$pkg_idx" "$now")
}

# ---- 进程存活检测 ----
is_game_alive() {
  pidof "$1" >/dev/null 2>&1 && return 0
  return 1
}

# ---- 解析 mBounds ----
parse_bounds() {
  local line="$1"
  # mBounds=Rect(left, top - right, bottom)
  # 示例: mBounds=Rect(0, 0 - 1080, 2400)
  local coords
  coords=$(echo "$line" | sed 's/.*Rect(\([0-9, ]*\) -.*/\1/' | tr -d ' ')
  echo "$coords"
}

# ---- 检测窗口状态 ----
check_pkg() {
  local pkg="$1" idx="$2"

  local now
  now=$(date +%s)

  # 检测是否运行
  local is_alive=false
  if is_game_alive "$pkg"; then
    is_alive=true
  fi

  local was_alive
  was_alive=$(get_val "$LAST_ALIVE" "$idx")

  # 检测到新启动
  if [ "$is_alive" = true ] && [ "$was_alive" = false ]; then
    log -t GAFix "🎮 [$pkg] 检测到新启动，等待稳定..."
    START_TIME=$(set_val "$START_TIME" "$idx" "$now")
    LAST_WAS_SMALL=$(set_val "$LAST_WAS_SMALL" "$idx" "false")
    LAST_FULLSCREEN=$(set_val "$LAST_FULLSCREEN" "$idx" "false")
    LAST_ALIVE=$(set_val "$LAST_ALIVE" "$idx" "true")
    return
  fi

  # 更新存活状态
  LAST_ALIVE=$(set_val "$LAST_ALIVE" "$idx" "$is_alive")

  # 游戏不在运行 → 跳过
  [ "$is_alive" = false ] && return

  # 检查是否在稳定期内
  local start_ts
  start_ts=$(get_val "$START_TIME" "$idx")
  local stable_elapsed=$(( now - start_ts ))
  if [ "$stable_elapsed" -lt "$STABILIZE_TIME" ]; then
    # 稳定期内，不更新状态
    return
  fi

  local window_block
  window_block=$(dumpsys window windows 2>/dev/null | grep -A 60 "Window.*${pkg}" | head -60)
  [ -z "$window_block" ] && return

  local bounds_line
  bounds_line=$(echo "$window_block" | grep 'mBounds=Rect(' | head -1)
  [ -z "$bounds_line" ] && return

  # 解析边界
  local coords
  coords=$(parse_bounds "$bounds_line")
  # coords 格式: left,top,right,bottom
  local left top right bottom
  left=$(echo "$coords" | cut -d, -f1)
  top=$(echo "$coords" | cut -d, -f2)
  right=$(echo "$coords" | cut -d, -f3)
  bottom=$(echo "$coords" | cut -d, -f4)

  # 更严格的全屏判断：左上角(0,0) 且 右下角接近屏幕分辨率
  local is_fullscreen=false
  local is_small=false

  if [ "$left" = "0" ] && [ "$top" = "0" ]; then
    # 检查右下角是否接近全屏（允许小误差）
    local right_match=false
    local bottom_match=false
    [ "$right" = "$W" ] && right_match=true
    [ "$right" = "$((W-1))" ] && right_match=true
    [ "$bottom" = "$H" ] && bottom_match=true
    [ "$bottom" = "$((H-1))" ] && bottom_match=true
    
    if [ "$right_match" = true ] || [ "$bottom_match" = true ]; then
      is_fullscreen=true
    else
      # 左上角是0,0 但尺寸不对，可能是中间态，暂不判断
      :
    fi
  else
    # 非全屏且边界值合理 → 小窗
    if [ -n "$right" ] && [ "$right" -gt 0 ] 2>/dev/null; then
      is_small=true
    fi
  fi

  local was_small
  was_small=$(get_val "$LAST_WAS_SMALL" "$idx")

  # 只在明确的 小窗→全屏 转换时触发
  if [ "$is_fullscreen" = true ] && [ "$was_small" = true ]; then
    trigger_rebuild "$pkg" "$idx"
  fi

  # 只在状态明确时更新
  if [ "$is_fullscreen" = true ] || [ "$is_small" = true ]; then
    LAST_WAS_SMALL=$(set_val "$LAST_WAS_SMALL" "$idx" "$is_small")
    LAST_FULLSCREEN=$(set_val "$LAST_FULLSCREEN" "$idx" "$is_fullscreen")
  fi
}

# ---- 主循环 ----
while true; do
  i=0
  while [ $i -lt $PKGT_COUNT ]; do
    check_pkg "${TARGET_PKGS[$i]}" "$i"
    i=$((i+1))
  done
  sleep "$INTERVAL"
done
