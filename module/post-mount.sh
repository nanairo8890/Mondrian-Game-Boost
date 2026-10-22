#!/system/bin/sh
# Mondrian-Game-Boost: NoMount has injected the module's powerhint.json; restart the power HAL so it
# reads it, still before zygote (see common.sh).
MODDIR=${0%/*}
. "$MODDIR/common.sh"

restart_hal
