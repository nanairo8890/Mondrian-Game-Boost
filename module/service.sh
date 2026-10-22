#!/system/bin/sh
# Mondrian-Game-Boost: makes sure the restarted power HAL is up (system_server waits for it), then,
# once Android is up, writes the state to module.prop (shown in the manager) and to game-boost.log.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

watch_hal

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
sleep 10

lang_init
s=$(state)
set_desc
{
  date
  echo "$s"
  echo "level: $(level); post-fs-data: $(active); power HAL: $(hal_state), $(getprop init.svc.$HAL_SVC)"
  echo "metamodule: $(metamodule)"
  b=$(nm_bin) && echo "nm rule: $("$b" rule list 2>/dev/null | grep -F "$HINTS")"
  echo "$HINTS: $(ls -Z "$HINTS" 2>/dev/null)"
  echo "GAME: $(game_row)"
  echo "sconfig: $(cat /sys/class/thermal/thermal_message/sconfig 2>/dev/null)"
} > "$MODDIR/game-boost.log" 2>&1
