#!/system/bin/sh
# Mondrian-Game-Boost: the module's Action button in the manager. Picks the other level and puts it
# in place at once when the boost runs (apply_level: only the power HAL restarts); otherwise it
# waits for the next boot.
MODDIR=${0%/*}
. "$MODDIR/common.sh"
lang_init

if [ "$(level)" = maximo ]; then echo alto > "$LEVEL_FILE"; else echo maximo > "$LEVEL_FILE"; fi

echo "Mondrian-Game-Boost $(mod_version)"
echo
if [ "$(level)" = maximo ]; then
  msg 'Nivel elegido: MÁXIMO' 'Level picked: MAXIMUM'
  msg '  Mientras juegas: perfil térmico sin límites de Xiaomi (nada hasta 51 °C), todos los' \
      "  While you play: Xiaomi's no-limits thermal profile (nothing below 51 °C), every core"
  msg '  núcleos y la GPU a su frecuencia máxima y la CPU sin reposo profundo. Más FPS, pero' \
      '  and the GPU at their top frequency and no deep CPU idle. More FPS, but it gets very'
  msg '  calienta mucho y gasta más batería; pasados los 51 °C el sistema baja la velocidad fuerte.' \
      '  hot and drains more battery; past 51 °C the system slows it down hard.'
else
  msg 'Nivel elegido: ALTO Y ESTABLE' 'Level picked: HIGH AND STEADY'
  msg '  Mientras juegas: perfil térmico de juegos de Xiaomi (sin límite de CPU hasta 45 °C),' \
      "  While you play: Xiaomi's gaming thermal profile (no CPU cap below 45 °C), CPU, GPU"
  msg '  CPU, GPU (mínimo 580 MHz) y memoria arriba sin quedar fijas al tope. Calienta menos y' \
      '  (580 MHz minimum) and memory up without being pinned at the top. It heats up less and'
  msg '  mantiene los FPS por más tiempo en juegos pesados.' \
      '  keeps the FPS up for longer in heavy games.'
fi
echo
msg 'Aplicando (se reinicia solo el power HAL, no el teléfono)...' \
    'Applying (only the power HAL restarts, not the phone)...'
apply_level
case $? in
  0) msg '>> Listo: el nivel ya está funcionando, sin reiniciar. <<' \
         '>> Done: the level is running now, no reboot needed. <<' ;;
  2) msg '>> El power HAL no aceptó la config: volvió a la de la ROM y el módulo se desactivó. <<' \
         ">> The power HAL did not take the config: it is back on the ROM's and the module disabled itself. <<" ;;
  *) msg '>> El boost no está activo en este arranque: el nivel se aplica al reiniciar. <<' \
         '>> The boost is not active this boot: the level applies after a reboot. <<' ;;
esac
msg 'Toca Acción otra vez para elegir el otro nivel.' 'Tap Action again to pick the other level.'
echo
msg 'El módulo pone solo el perfil térmico de juegos: deja apagado "Use thermal profiles" en' \
    'The module sets the gaming thermal profile by itself: leave "Use thermal profiles" off in'
msg 'Configuración > Sistema > Thermal profiles, para que no se pisen.' \
    'Settings > System > Thermal profiles, so they do not overwrite each other.'
msg 'Si un juego no activa el boost, agrégalo en Game Space.' \
    'If a game does not get the boost, add it in Game Space.'
echo
state
set_desc
