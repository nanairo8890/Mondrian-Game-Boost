#!/system/bin/sh
# Mondrian-Game-Boost: puts the chosen level's power HAL config where NoMount will inject it (its
# metamount.sh runs after this), or skips the injection if the ROM's config changed.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

# The WebUI's list of thermal zones is valid for one boot (zone numbers follow the driver load order),
# and its SoC/GPU/driver line is found again in case a ROM update brought another driver
rm -f "$MODDIR"/.zones-* "$MODDIR/.hwinfo"
pick_config
