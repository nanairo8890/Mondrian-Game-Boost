# Mondrian-Game-Boost

Módulo root que da más rendimiento en juegos a través del power HAL de la ROM, con un panel web
para ver qué está pasando.

*English below.*

## Funciona en

| | |
| --- | --- |
| **Dispositivo** | **POCO F5 Pro / Redmi K60 (`mondrian`)**. Ningún otro. |
| **Custom ROM** | **Project Infinity-X 4.1**, build 17.10.2026 (Android 17). Probada en el teléfono: boost verificado con un juego. |
| | **MistOS 5.1 Beta**, build 20261011 (Android 17). Trae exactamente el mismo `powerhint.json` (mismo sha256); no probada en el teléfono. |
| **Root** | KernelSU o un fork (BakaSU, ReSukiSU) **con NoMount**: un kernel con NoMount (por ejemplo Equinox BakaSU Edition r2 o más nuevo) y el metamódulo oficial de NoMount de maxsteeel. |
| **Android** | 14 o más nuevo. |

## No funciona en

| | Qué pasa |
| --- | --- |
| Otro teléfono | El instalador se niega. |
| Magisk o APatch | El instalador se niega. |
| Otras ROMs de mondrian (otras customs, HyperOS, o una build de Infinity-X o MistOS con otro `powerhint.json`) | Se instala, pero el boost queda apagado solo: el módulo comprueba en cada arranque (sha256) que el `/vendor/etc/powerhint.json` de la ROM sea el que conoce byte a byte, y si no lo es no inyecta nada. Solo se aplican los ajustes de ART. |
| Sin NoMount | Se instala, pero solo se aplican los ajustes de ART. |

El módulo compara el archivo, no el nombre de la ROM: una build nueva que traiga el mismo
`powerhint.json` funciona igual, y una con otro queda con el boost apagado (el panel web lo dice).
Para agregar una ROM hace falta su `powerhint.json` (ver "Compilar").

El módulo no toca el kernel, las particiones ni los drivers. NoMount pone un archivo encima del
de la ROM y los ajustes de ART son propiedades del sistema: si lo desinstalas, todo vuelve a
como estaba.

## Qué hace

- **Boost de juegos.** Android le avisa al power HAL cuando un juego está en pantalla (modo
  `GAME`), pero el `powerhint.json` de estas ROMs no tiene acciones para ese modo. NoMount pone
  encima una copia de la config de la ROM con las acciones de juego, y el módulo reinicia el power
  HAL una vez durante el arranque para que la lea. Al salir del juego todo vuelve a lo normal.
- **Perfil térmico de juegos automático.** El perfil normal de Xiaomi limita el núcleo principal a
  2,25 GHz y los grandes a 2,57 GHz desde 25 °C de cuerpo. Mientras hay un juego en pantalla, el
  módulo pone el perfil de juegos (o el sin límites, en el nivel máximo) y al salir vuelve al
  normal.
- **Dos niveles**, que eliges con el botón Acción o en el panel web y se aplican al instante, sin
  reiniciar el teléfono (solo se reinicia el power HAL, en unos 2 segundos):
  - *Alto y estable* (por defecto): sin límite de CPU hasta 45 °C, pisos de 1,56 GHz en los
    núcleos grandes, 1,65 GHz en el principal y 580 MHz en la GPU, y memoria y caché más altas.
  - *Máximo*: sin límites hasta 51 °C, CPU y GPU fijas al máximo y sin reposo profundo. Más FPS,
    mucho más calor y gasto de batería.
- **Ajustes de ART de MistOS 5.1**: heap de 512 MB, caché JIT más grande, precarga de código y
  procesos USAP listos de antemano.

## Panel web

El botón del panel web del módulo en el manager (o la app KsuWebUI) abre un panel de
instrumentos en el idioma del teléfono (11 idiomas, inglés si el tuyo no está):

- Estado del boost, procesador, GPU y versión del driver.
- Esferas de frecuencia (núcleo X2 y GPU) y de temperatura (CPU y cuerpo), con el tope térmico
  actual y el límite del nivel.
- Luces de modo juego, perfil térmico y tope térmico.
- Lo que cada nivel pone mientras juegas, con el valor de la ROM marcado.
- Monitor de hardware de los últimos 4 minutos mientras la página está abierta.

El panel es estático a propósito (sin animaciones ni desenfoques), para no cargar la GPU ni colgar
la app, y nunca deja un comando corriendo al cerrarse (el manager de BakaSU se cierra si un comando
de un panel ya cerrado sigue escribiendo).

En el manager, la descripción del módulo muestra solo el nivel elegido ("Nivel: Máximo"); si el
boost no funciona, también el motivo.

## Instalación

1. Instala un kernel con NoMount y el metamódulo oficial de NoMount, y reinicia.
2. Instala `Mondrian-Game-Boost-v1.0.zip` desde el manager y reinicia.
3. Deja apagado "Use thermal profiles" (Configuración > Sistema > Thermal profiles): el módulo ya
   pone el perfil térmico en los juegos y los dos se pisarían.

## Protecciones contra cuelgues en el arranque

- La config del módulo solo se inyecta si el `powerhint.json` de la ROM es el que conoce el
  módulo. Si no, `skip_mount`.
- El power HAL solo se reinicia si el archivo inyectado es el del módulo y tiene la etiqueta
  SELinux correcta. Si no, el módulo quita la regla de NoMount.
- Si después de reiniciarlo el power HAL se cae, el módulo quita la regla de NoMount, le devuelve
  la config de la ROM, lo reinicia y se desactiva solo. La descripción del módulo dice qué pasó.

**Si aun así el teléfono no arranca:**

- **Modo seguro:** presiona bajar volumen 3 veces durante el arranque, después del logo. KernelSU
  o BakaSU arranca con todos los módulos desactivados. Después borra o desactiva este módulo en el
  manager.
- **Desde el recovery** (OrangeFox, TWRP): crea un archivo vacío
  `/data/adb/modules/mondrian_game_boost/disable`, o borra esa carpeta, y reinicia.

## Comprobar que funciona

En el panel web: "Boost activo", NoMount "Activo" y Power HAL "Con la config del módulo". Con un
juego abierto, la luz de modo juego se enciende y el perfil térmico pasa a "Juegos".

Por adb, con un juego en pantalla, el perfil térmico es `13` (alto y estable) o `10` (máximo); sin
juego vuelve a `0`:

```
adb shell cat /sys/class/thermal/thermal_message/sconfig
```

Con root para la shell (dáselo en el manager), la fila `GAME` cuenta los juegos abiertos y
`sched_upmigrate` dice `90 80` mientras juegas:

```
adb shell "su -c 'dumpsys android.hardware.power.IPower/default | grep ^GAME; cat /proc/sys/walt/sched_upmigrate'"
```

## Compilar

```
./build.sh
```

Necesita `python3`, `zip` y `sha256sum`. Genera las dos configs (`tools/gen_powerhint.py`) a partir
de `ref/powerhint-infinityx-20261017.json`, las comprueba con las reglas que aplica libperfmgr y
arma `out/Mondrian-Game-Boost-<versión>.zip`.

## Créditos

- `powerhint.json` base: el árbol de mondrian de la ROM (LineageOS, `power-libperfmgr`).
- Valores de ART: MistOS 5.1 (LF5).
- NoMount: maxsteeel (https://github.com/maxsteeel/nomount).

---

## English

Root module that gives games more performance through the ROM's power HAL, with a WebUI that
shows what is going on.

### Works on

| | |
| --- | --- |
| **Device** | **POCO F5 Pro / Redmi K60 (`mondrian`)** only. |
| **Custom ROM** | **Project Infinity-X 4.1**, build 17.10.2026 (Android 17). Tested on the phone: boost checked with a game. |
| | **MistOS 5.1 Beta**, build 20261011 (Android 17). Ships exactly the same `powerhint.json` (same sha256); not tested on the phone. |
| **Root** | KernelSU or a fork (BakaSU, ReSukiSU) **with NoMount**: a kernel with NoMount (for example Equinox BakaSU Edition r2 or newer) plus maxsteeel's official NoMount metamodule. |
| **Android** | 14 or newer. |

### Does not work on

| | What happens |
| --- | --- |
| Any other phone | The installer refuses. |
| Magisk or APatch | The installer refuses. |
| Other mondrian ROMs (other customs, HyperOS, or an Infinity-X or MistOS build with another `powerhint.json`) | It installs, but the boost stays off by itself: every boot it checks (sha256) that the ROM's `/vendor/etc/powerhint.json` is the one it knows byte for byte, and injects nothing otherwise. Only the ART settings apply. |
| No NoMount | It installs, but only the ART settings apply. |

It compares the file, not the ROM's name: a new build that ships the same `powerhint.json` works
too, and one with another file keeps the boost off (the WebUI says so).

The module does not touch the kernel, partitions or drivers: NoMount overlays one file and the ART
settings are system properties, so uninstalling it puts everything back.

### What it does

While a game is on screen (Android's `GAME` power mode) it raises CPU, GPU and memory floors and
switches Xiaomi's thermal scene to the gaming one (no CPU cap below 45 °C) or, on the Maximum
level, to the no-limits one (51 °C). Two levels, picked with the Action button or the WebUI, apply
at once without rebooting the phone (only the power HAL restarts, in about 2 seconds). It also
applies MistOS 5.1's ART settings. The module's description in the manager shows only the picked
level, plus the reason when the boost is not working. The WebUI (11 languages) shows the
state, the processor, GPU and driver, clock and temperature gauges, what each level sets, and a
hardware monitor of the last 4 minutes.

### Boot safety

The module's config is only injected over the ROM's known file; the power HAL is only restarted
when the injected file is the module's and carries the right SELinux label; if the power HAL then
dies, the module drops the NoMount rule, gives it the ROM's config back and disables itself. If the
phone still does not boot: press volume down 3 times during boot for KernelSU's safe mode, or from
recovery create `/data/adb/modules/mondrian_game_boost/disable` (or delete that folder).

### Install

1. Install a kernel with NoMount and the official NoMount metamodule, and reboot.
2. Install `Mondrian-Game-Boost-v1.0.zip` from the manager and reboot.
3. Leave "Use thermal profiles" (Settings > System > Thermal profiles) off.

### Credits

Base `powerhint.json`: the ROM's mondrian tree (LineageOS, `power-libperfmgr`). ART values:
MistOS 5.1 (LF5). NoMount: maxsteeel.

Author: Nanairo8890.
