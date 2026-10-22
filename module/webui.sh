#!/system/bin/sh
# Mondrian-Game-Boost: data for the module's WebUI (webroot/index.html), which runs it as root
# through the manager's ksu.exec / ksu.spawn. Prints JSON, one object per line.
#
#   webui.sh status             module state as codes (the page translates them)
#   webui.sh live               CPU/GPU frequencies, temperatures, game mode, thermal scene, and
#                               the CPU time, memory and battery counters of the hardware monitor
#   webui.sh stream N           "live" every 1.5 s, N times (for testing; the page polls "live")
#   webui.sh level alto|maximo  picks the level and puts it in place now if the boost runs (only the
#                               power HAL restarts), then prints the status
#   webui.sh reboot             restarts the phone
#   webui.sh log                game-boost.log as a JSON string
MODDIR=${0%/*}
. "$MODDIR/common.sh"

# A JSON string, quotes included: newlines and tabs kept as \n and \t, other control characters
# dropped, and % written as % (a manager may hand the output to the page in a javascript:
# URL, which would percent-decode it). No tr: Android's toybox tr takes '\000-\010' apart and
# deletes every "-". Print the result with printf, never echo: mksh's echo expands backslashes.
js() {
  printf '"%s"' "$(printf '%s' "$1" |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/[[:cntrl:]]//g' -e 's/%/\\u0025/g' |
    awk '{ printf "%s%s", s, $0; s = "\\n" }')"
}
jb() { if "$@"; then echo true; else echo false; fi; }

# Reads the leading integer of file $1 into R without forking; $2 (default 0) if there is none
rd() {
  R=
  { read -r R < "$1"; } 2>/dev/null
  R=${R%%[!0-9-]*}
  case $R in ''|-|?*-*) R=${2:-0} ;; esac
}

status() {
  loc=$(sys_locale)
  case $loc in es*) ES=1 ;; *) ES=0 ;; esac
  echo $ES > "$MODDIR/.lang"
  GAME_ROW=$(game_row)     # state_code uses it instead of asking the power HAL again
  code=$(state_code)
  count=$(printf '%s\n' "$GAME_ROW" | cut -f2 | head -n 1)
  case $count in ''|*[!0-9]*) count=null ;; esac
  printf '%s\n' "{\"version\":$(js "$(mod_version)"),\"level\":$(js "$(level)"),\"active\":$(js "$(active)"),\"hal\":$(js "$(hal_state)"),\"code\":$(js "$code"),\"ok\":$([ "$code" = active ] && echo true || echo false),\"late\":$(jb hal_late),\"locale\":$(js "$loc"),\"metamodule\":$(js "$(metamodule)"),\"thermalProfiles\":$(jb thermal_profiles_on),\"gameCount\":$count,\"disabled\":$(jb [ -f "$MODDIR/disable" ]),$(hwinfo)}"
}

# The SoC model, the GPU model and the Adreno driver version, as JSON members; found once per boot
# (post-fs-data.sh clears the cache: a ROM update can bring another driver)
hwinfo() {
  f=$MODDIR/.hwinfo
  if [ ! -s "$f" ]; then
    gm=
    { read -r gm < /sys/class/kgsl/kgsl-3d0/gpu_model; } 2>/dev/null
    drv=$(grep -aoE 'V@[0-9]+\.[0-9]+' /vendor/lib64/egl/libGLESv2_adreno.so 2>/dev/null | head -n 1)
    printf '%s\n' "\"soc\":$(js "$(getprop ro.soc.model)"),\"gpuModel\":$(js "$gm"),\"driver\":$(js "$drv")" > "$f"
  fi
  cat "$f"
}

# Temperature files of the thermal zones whose type starts with $1, listed once per boot
# (post-fs-data.sh clears the cache: zone numbers follow the driver load order) into ZL
zones() {
  f=$MODDIR/.zones-$1
  if [ ! -f "$f" ]; then
    for z in /sys/class/thermal/thermal_zone*; do
      ty=
      { read -r ty < "$z/type"; } 2>/dev/null
      case $ty in "$1"*) echo "$z/temp" ;; esac
    done > "$f"
  fi
  ZL=
  while read -r l; do ZL="$ZL $l"; done < "$f"
}
# Hottest of those zones into H, in tenths of a degree, or null
hottest() {
  zones "$1"
  H=
  for z in $ZL; do
    rd "$z" x
    [ "$R" = x ] && continue
    { [ -z "$H" ] || [ "$R" -gt "$H" ]; } && H=$R
  done
  if [ -n "$H" ]; then H=$((H / 100)); else H=null; fi
}

live() {
  P=/sys/devices/system/cpu/cpufreq
  K=/sys/class/kgsl/kgsl-3d0
  M=/sys/class/thermal/thermal_message
  cc=; cm=; ct=
  for p in 0 4 7; do
    rd $P/policy$p/scaling_cur_freq; cc="$cc${cc:+,}$R"
    rd $P/policy$p/scaling_max_freq; cm="$cm${cm:+,}$R"
    rd $P/policy$p/cpuinfo_max_freq; ct="$ct${ct:+,}$R"
  done
  rd $K/gpuclk; g=$R
  # The GPU's top frequency is the first of its available ones; max_gpuclk is its current cap
  # (thermal and QoS limits lower it), like scaling_max_freq for the CPU
  rd $K/gpu_available_frequencies; gt=$R
  rd $K/max_gpuclk; gc=$R
  rd $K/gpu_busy_percentage; gb=$R
  rd $M/sconfig null; sc=$R
  rd $M/board_sensor_temp null; board=$R
  rd /sys/class/power_supply/battery/temp null; batt=$R
  hottest cpu; tc=$H
  hottest gpu; tg=$H
  a=; b=
  { read -r a b < /proc/sys/walt/sched_upmigrate; } 2>/dev/null
  game=false
  [ "$a $b" = "90 80" ] && game=true
  # CPU time counters (user nice system idle iowait irq softirq steal): the page turns two samples
  # into a usage, and adds them up itself (the shell's arithmetic may be 32-bit)
  s0=; s1=; s2=; s3=; s4=; s5=; s6=; s7=; s8=
  { read -r s0 s1 s2 s3 s4 s5 s6 s7 s8 rest < /proc/stat; } 2>/dev/null
  stat="$s1,$s2,$s3,$s4,$s5,$s6,$s7,$s8"
  case $s0,$stat in cpu,*[!0-9,]*|cpu,*,,*|cpu,,*|cpu,*,) stat= ;; cpu,*) ;; *) stat= ;; esac
  # MemTotal and MemAvailable, in kB (the first and third lines); -1 when they are not there
  k1=; k3=; mt=; ma=
  { { read -r k1 mt rest; read -r rest; read -r k3 ma rest; } < /proc/meminfo; } 2>/dev/null
  [ "$k1" = MemTotal: ] || mt=
  [ "$k3" = MemAvailable: ] || ma=
  case $mt in ''|*[!0-9]*) mt=0 ;; esac
  case $ma in ''|*[!0-9]*) ma=-1 ;; esac
  B=/sys/class/power_supply/battery
  rd $B/current_now null; bi=$R
  rd $B/voltage_now null; bv=$R
  bs=
  { read -r bs < $B/status; } 2>/dev/null
  chg=false
  [ "$bs" = Charging ] && chg=true
  echo "{\"cpu\":[$cc],\"cpuCap\":[$cm],\"cpuTop\":[$ct],\"gpu\":$g,\"gpuTop\":$gt,\"gpuCap\":$gc,\"gpuBusy\":$gb," \
       "\"tCpu\":$tc,\"tGpu\":$tg,\"tBatt\":$batt,\"tBoard\":$board,\"scene\":$sc,\"game\":$game," \
       "\"stat\":[$stat],\"mem\":[$mt,$ma],\"bI\":$bi,\"bV\":$bv,\"chg\":$chg}"
}

case $1 in
  status) status ;;
  live) live ;;
  stream)
    n=${2:-40}
    case $n in ''|*[!0-9]*) n=40 ;; esac
    while [ "$n" -gt 0 ]; do
      live
      n=$((n - 1))
      [ "$n" -gt 0 ] && { sleep 1.5 2>/dev/null || sleep 2; }
    done ;;
  level)
    case $2 in alto|maximo) echo "$2" > "$LEVEL_FILE"; apply_level >/dev/null 2>&1; lang_init; set_desc ;; esac
    status ;;
  log) js "$(cat "$MODDIR/game-boost.log" 2>/dev/null)"; echo ;;
  reboot) svc power reboot 2>/dev/null || reboot ;;
  *) echo '{"error":"usage"}' ;;
esac
