# Mondrian-Game-Boost: functions shared by the module scripts (sourced, never run on its own).
#
# Android's GameManager tells the power HAL when a game is the app on top (power mode GAME) and,
# for games in performance mode that report it, when one is loading (GAME_LOADING). The ROM's
# powerhint.json has no action for either, so nothing happens. NoMount puts the module's
# system/vendor/etc/powerhint.json (the ROM's plus game actions, one file per level) over
# /vendor/etc/powerhint.json; apps that BakaSU/SUSFS unmount still see the ROM's file.
#
# Boot order in ksud: module post-fs-data.sh (picks the level's file) -> system.prop -> NoMount's
# metamount.sh (adds the rules) -> post-mount.sh, all before zygote. The power HAL read its config
# at late-fs, before all that, so post-mount.sh restarts it; system_server asks it which modes it
# supports once, when it starts. A config the power HAL rejects makes it abort before it registers,
# and system_server waits for it forever: post-mount.sh and service.sh watch for that and give it
# the ROM's config back. The caller sets MODDIR.

HAL_SVC=vendor.power-hal-aidl
HAL_BIN=android.hardware.power-service.lineage-libperfmgr
HAL_NAME=android.hardware.power.IPower/default
HINTS=/vendor/etc/powerhint.json
OURS=$MODDIR/system/vendor/etc/powerhint.json   # system/vendor may be a symlink to ../vendor
ROM_COPY=$MODDIR/powerhint-rom.json             # the ROM's file (sha256 BASE_SHA)
LEVEL_FILE=$MODDIR/level     # alto | maximo, picked with the Action button
ACTIVE_FILE=$MODDIR/.active  # level put in place by post-fs-data.sh this boot, or mismatch
HAL_FILE=$MODDIR/.hal        # what post-mount.sh / service.sh did with the power HAL this boot
CONF_CON=u:object_r:vendor_configs_file:s0
# sha256 of the powerhint.json the module's files are built from (Project Infinity-X 4.1
# 20261017; MistOS 5.1 Beta 20261011 ships the same file)
BASE_SHA=@BASE_SHA@

# The phone's language (first of the languages picked in Settings, e.g. es-CL; system_locales needs
# Android up). Script messages are in Spanish when it is Spanish and in English otherwise, as in
# SIM-APN-Config; the WebUI translates the state codes itself.
sys_locale() {
  l=$(settings get system system_locales 2>/dev/null)
  [ -z "$l" ] || [ "$l" = null ] && l=$(getprop persist.sys.locale)
  [ -z "$l" ] && l=$(getprop ro.product.locale)
  echo "${l%%,*}"
}
ES=0
lang_init() {
  case $(sys_locale) in
    es*) ES=1 ;;
    *) ES=0 ;;
  esac
  echo $ES > "$MODDIR/.lang"
}
# Before Android is up (post-mount): the language seen at install or on the last boot
lang_saved() { [ "$(cat "$MODDIR/.lang" 2>/dev/null)" = 1 ] && ES=1 || ES=0; }
msg() { if [ $ES = 1 ]; then echo "$1"; else echo "$2"; fi; }

mod_version() { sed -n 's/^version=//p' "$MODDIR/module.prop"; }

level() { [ "$(cat "$LEVEL_FILE" 2>/dev/null)" = maximo ] && echo maximo || echo alto; }
active() { cat "$ACTIVE_FILE" 2>/dev/null; }
hal_state() { cat "$HAL_FILE" 2>/dev/null; }

level_name() {
  if [ "$1" = maximo ]; then msg 'máximo' 'maximum'; else msg 'alto y estable' 'high and steady'; fi
}

# Only right before NoMount's rules exist (post-fs-data) or for an app it hides them from does
# /vendor/etc/powerhint.json show the ROM's file
rom_ok() { [ "$(sha256sum "$HINTS" 2>/dev/null | cut -d' ' -f1)" = "$BASE_SHA" ]; }

# post-fs-data: the file NoMount will inject is the chosen level's, or nothing if the ROM's config
# is not the one the module's files are built from (they replace it whole)
pick_config() {
  rm -f "$HAL_FILE"
  if rom_ok; then
    cat "$MODDIR/powerhint-$(level).json" > "$OURS" &&
      chmod 0644 "$OURS" && chcon "$CONF_CON" "$OURS" || { echo error > "$ACTIVE_FILE"; touch "$MODDIR/skip_mount"; return 1; }
    rm -f "$MODDIR/skip_mount"
    level > "$ACTIVE_FILE"
  else
    touch "$MODDIR/skip_mount"
    echo mismatch > "$ACTIVE_FILE"
  fi
}

metamodule() { readlink /data/adb/metamodule 2>/dev/null; }
nm_bin() {
  for b in /data/adb/metamodule/bin/nm /data/adb/modules/nomount/bin/nm; do
    [ -x "$b" ] && { echo "$b"; return 0; }
  done
  return 1
}

# NoMount serves the module's file at /vendor/etc/powerhint.json, with the label the power HAL may read
overlay_ok() { [ -f "$OURS" ] && cmp -s "$OURS" "$HINTS"; }
label_ok() { ls -Z "$HINTS" 2>/dev/null | grep -q "$CONF_CON"; }

# Pid of the running power HAL; nothing while init has it stopped or restarting (init publishes
# init.svc_debug_pid.<service>; pidof if it does not)
hal_pid() {
  s=$(getprop "init.svc.$HAL_SVC")
  [ -z "$s" ] || [ "$s" = running ] || return 0
  p=$(getprop "init.svc_debug_pid.$HAL_SVC")
  [ -n "$p" ] && { echo "$p"; return 0; }
  pidof "$HAL_BIN" 2>/dev/null
}
hal_registered() { service check "$HAL_NAME" 2>/dev/null | grep -q ': found'; }

# Watches the power HAL for up to $1 s after a restart ($2: its pid before, if known).
# Up: registered, or the same pid seen running 4 s in a row (on a config it rejects it aborts within
# milliseconds, and init restarts it every 5 s). Down: init shows it restarting, or it comes back
# with yet another pid. Returns 0 if up, 1 if down, 2 if neither could be told (no restart seen yet,
# or no pid to look at): then nothing is touched.
hal_up() {
  n=0; same=0; last=; first=; changed=0; down=0
  [ -z "$2" ] && changed=1
  while [ $n -lt "$1" ]; do
    s=$(getprop "init.svc.$HAL_SVC")
    p=$(hal_pid)
    [ "$p" != "$2" ] && changed=1
    if [ $changed = 1 ]; then
      [ "$s" = restarting ] && down=1
      if [ -n "$p" ]; then
        hal_registered && return 0
        [ -z "$first" ] && first=$p
        [ "$p" != "$first" ] && down=1
        if [ "$p" = "$last" ]; then same=$((same + 1)); else same=0; fi
        [ $same -ge 4 ] && return 0
      fi
    fi
    last=$p
    sleep 1
    n=$((n + 1))
  done
  [ $down = 1 ] && return 1
  return 2
}

# The power HAL keeps aborting with the module's config: drop NoMount's rule (or, if that fails,
# serve the ROM's content through it), restart the power HAL and turn the module off for the next boot
heal() {
  b=$(nm_bin) && "$b" rule del "$HINTS" >/dev/null 2>&1
  cmp -s "$OURS" "$HINTS" && cat "$ROM_COPY" > "$OURS"
  touch "$MODDIR/disable"
  echo "healed-$1" > "$HAL_FILE"
  setprop ctl.restart "$HAL_SVC"
  # A disabled module's service.sh does not run: say it here
  lang_saved
  s=$(state)
  set_desc
  { date; echo "$s"; echo "power HAL: healed in $1"; } > "$MODDIR/game-boost.log" 2>&1
}

# post-mount: restart the power HAL so it reads the injected file, and wait (10 s at most) for the
# new instance to be up. If init has not restarted it yet, service.sh checks it later.
restart_hal() {
  [ -f "$MODDIR/skip_mount" ] && { echo skip > "$HAL_FILE"; return 0; }
  overlay_ok || { echo no-overlay > "$HAL_FILE"; return 0; }
  # A label the power HAL cannot read would make it abort: keep the ROM's config it already runs,
  # and drop the rule, because the ROM restarts the power HAL whenever zygote restarts
  if ! label_ok; then
    b=$(nm_bin) && "$b" rule del "$HINTS" >/dev/null 2>&1
    echo bad-label > "$HAL_FILE"
    return 0
  fi
  old=$(hal_pid)
  setprop ctl.restart "$HAL_SVC"
  echo restarted > "$HAL_FILE"
  sleep 1
  hal_up 10 "$old"
  case $? in
    0) echo ok > "$HAL_FILE" ;;
    2) echo pending > "$HAL_FILE" ;;
    *) heal post-mount ;;
  esac
}

# The chosen level, now, without a reboot: its config goes into the file NoMount serves and only the
# power HAL restarts. system_server and SurfaceFlinger reconnect to it by themselves, and these
# configs have no ADPF sessions to lose; the WebUI and the Action button run this while the manager,
# not a game, is on screen. Only while the boost works this boot. Returns 0 when the level is active,
# 1 when it waits for the next boot, 2 when the power HAL rejected it (healed, like at boot).
apply_level() {
  lv=$(level)
  # nothing to do only if the file being served is already that level's
  [ "$lv" = "$(active)" ] && cmp -s "$MODDIR/powerhint-$lv.json" "$OURS" && return 0
  [ "$(state_code)" = active ] && [ ! -f "$MODDIR/disable" ] || return 1
  overlay_ok && label_ok || return 1
  cat "$MODDIR/powerhint-$lv.json" > "$OURS" || return 1
  old=$(hal_pid)
  setprop ctl.restart "$HAL_SVC"
  sleep 1
  hal_up 10 "$old"
  case $? in
    0) echo "$lv" > "$ACTIVE_FILE"; echo ok > "$HAL_FILE"; return 0 ;;
    1) heal live; return 2 ;;
    # not told apart within 10 s: it reads the new file whenever it comes up
    *) echo "$lv" > "$ACTIVE_FILE"; echo late > "$HAL_FILE"; return 0 ;;
  esac
}

# service: the same watch once more, for a restart init did after post-mount.sh returned
watch_hal() {
  case $(hal_state) in
    restarted|pending) ;;
    *) return 0 ;;
  esac
  hal_up 30 ""
  r=$?
  # post-mount.sh may still be running (past ksud's deadline) and may have healed meanwhile
  case $(hal_state) in healed-*) return 0 ;; esac
  case $r in
    # pending: restarted after post-fs-data, system_server may have asked the old one for its modes
    0) [ "$(hal_state)" = pending ] && echo late > "$HAL_FILE" || echo ok > "$HAL_FILE" ;;
    1) heal service ;;
  esac
}

# The running power HAL has the module's config: only it has a GAME hint, and the dump lists every
# hint as "<name>\t<count>\t<duration ms>"
game_row() { dumpsys "$HAL_NAME" 2>/dev/null | grep "^GAME$(printf '\t')"; }

# XiaomiParts' per-app thermal profiles (off by default) write the same thermal scene file on every
# app switch, so it and the module overwrite each other
thermal_profiles_on() { dumpsys activity services org.lineageos.settings 2>/dev/null | grep -q 'thermal.ThermalService'; }

# The state as a code (the WebUI translates it): active, reboot, mismatch, error, no-nomount,
# nomount-disabled, nomount-safe, nomount-noinject, bad-label, healed, notran, noconfig
state_code() {
  case $(active) in
    mismatch|error) active; return ;;
    alto|maximo) ;;
    *) echo reboot; return ;;
  esac
  case $(hal_state) in
    no-overlay)
      if [ -z "$(metamodule)" ]; then echo no-nomount
      elif [ -f /data/adb/metamodule/disable ]; then echo nomount-disabled
      elif [ -f /data/adb/nomount/disable ]; then echo nomount-safe
      else echo nomount-noinject
      fi
      return ;;
    bad-label) echo bad-label; return ;;
    healed-*) echo healed; return ;;
    '') echo notran; return ;;
  esac
  # webui.sh status passes the row it already read in GAME_ROW
  if [ -z "${GAME_ROW-$(game_row)}" ]; then echo noconfig; else echo active; fi
}

# The power HAL restarted after post-fs-data: system_server may have asked the old one for its modes
hal_late() { case $(hal_state) in late|pending|restarted) return 0 ;; esac; return 1; }

# One-line state for the manager; returns 0 if the game boost works
state() {
  case $(state_code) in
    mismatch)
      msg 'Boost de juegos inactivo: el power HAL de esta ROM no es el que conoce el módulo' \
          "Game boost inactive: this ROM's power HAL config is not the one the module knows" ;;
    error)
      msg 'Error: no se pudo preparar el archivo del módulo' 'Error: could not prepare the module file' ;;
    reboot)
      msg 'Boost de juegos inactivo: reinicia el teléfono' 'Game boost inactive: reboot the phone' ;;
    no-nomount)
      msg 'Boost de juegos inactivo: falta NoMount (instálalo y reinicia)' \
          'Game boost inactive: NoMount is missing (install it and reboot)' ;;
    nomount-disabled)
      msg 'Boost de juegos inactivo: NoMount está desactivado en el manager' \
          'Game boost inactive: NoMount is disabled in the manager' ;;
    nomount-safe)
      msg 'Boost de juegos inactivo: NoMount está en modo seguro (/data/adb/nomount/disable)' \
          'Game boost inactive: NoMount is in safe mode (/data/adb/nomount/disable)' ;;
    nomount-noinject)
      msg 'Boost de juegos inactivo: NoMount no inyectó el archivo (mira /data/adb/nomount/nomount.log)' \
          'Game boost inactive: NoMount did not inject the file (see /data/adb/nomount/nomount.log)' ;;
    bad-label)
      msg 'Boost de juegos inactivo: el archivo inyectado no tiene la etiqueta SELinux vendor_configs_file' \
          'Game boost inactive: the injected file does not have the vendor_configs_file SELinux label' ;;
    healed)
      msg 'El power HAL no aceptó la config del módulo: se le devolvió la de la ROM y el módulo quedó desactivado' \
          "The power HAL did not take the module's config: it got the ROM's back and the module is now disabled" ;;
    notran)
      msg 'Boost de juegos inactivo: el módulo no corrió en este arranque' \
          'Game boost inactive: the module did not run this boot' ;;
    noconfig)
      msg 'Boost de juegos inactivo: el power HAL no tiene la config del módulo' \
          "Game boost inactive: the power HAL does not have the module's config" ;;
    active)
      s=$(msg "Boost de juegos activo, nivel $(level_name "$(active)")" \
              "Game boost active, level $(level_name "$(active)")")
      hal_late && s="$s $(msg '(el power HAL se reinició tarde: si los juegos no lo activan, reinicia)' \
                              '(the power HAL restarted late: if games do not trigger it, reboot)')"
      [ "$(level)" != "$(active)" ] && s="$s $(msg "(pasa a $(level_name "$(level)") al reiniciar)" \
                                                  "(switches to $(level_name "$(level)") on reboot)")"
      thermal_profiles_on && s="$s $(msg '(apaga "Use thermal profiles" en Configuración > Sistema: sobrescribe el perfil térmico del módulo)' \
                                         '(turn off "Use thermal profiles" in Settings > System: it overwrites the module)')"
      echo "$s"
      return 0 ;;
  esac
  return 1
}

# The description in the manager: only the level the user picked while the boost works ("Nivel:
# Máximo"); when it does not, the reason after it, since the manager shows nothing else
set_desc() {
  p=$MODDIR/module.prop
  if [ "$(level)" = maximo ]; then d=$(msg 'Nivel: Máximo' 'Level: Maximum')
  else d=$(msg 'Nivel: Alto y estable' 'Level: High and steady'); fi
  if [ "$(state_code)" = active ]; then
    [ "$(level)" = "$(active)" ] || d="$d $(msg '(al reiniciar)' '(after a reboot)')"
  else
    d="$d · $(state)"
  fi
  { grep -v '^description=' "$p"; echo "description=$d"; } > "$p.tmp" &&
    mv -f "$p.tmp" "$p"
}
