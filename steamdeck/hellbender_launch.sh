#!/bin/bash
# Hellbender (Terminal Reality / Microsoft, 1996) Steam Deck launch wrapper.
#
# Keep it beside game/ (build.py puts it there). With the folder at /home/deck/Games/Hellbender:
#   Shortcut target: /home/deck/Games/Hellbender/game/HELLBEND.EXE, Start In: .../game/
#   Compatibility: Proton 11.0 (WoW64 mode, below; Proton 9.0 crashes in libX11 after a while)
#   Launch Options: /home/deck/Games/Hellbender/hellbender_launch.sh %command%
#
# HELLBEND.EXE is the disc's v1.01 patched (patch_exe.py): the game's Direct3D in its DirectDraw full screen through
# dgVoodoo2 (or RENDERER=software: its software renderer in a GDI window), 4:3 with black bars, the pad through XInput
# as the game's joystick and keys, at most 60 frames a second, no busy waits, no pointer over the game, no menu bar.
# It reads everything from its own folder (it makes it the current one): system\HELLBEND.INI (settings), system\*.POD
# (data), system\Story\*.SMK (movies), and writes data\ (saved games, scores).
# DLL overrides: winmm = ogg-winmm beside the exe (the CD music from Music\Track02..09.ogg; winmm.ini); ddraw / d3dimm
# = dgVoodoo2 (RENDERER=d3d) or Wine's (RENDERER=software, unused). Wine's X input method off (UseXIM=N, below).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/launch.log"
log() { echo "[$(date '+%H:%M:%S')] $*" >>"$LOG"; }
: >"$LOG"
log "args: $*"
log "cwd: $(pwd)"
log "STEAM_COMPAT_DATA_PATH=${STEAM_COMPAT_DATA_PATH:-unset}"

# Renderer: RENDERER=d3d (default) = the
# game's Direct3D in its DirectDraw full screen, both through dgVoodoo2 2.79.3 (ddraw.dll + d3dimm.dll beside the exe, dgVoodoo.conf: 2x
# internal resolution, 4:3, 60 fps); RENDERER=software = the game's own 640x480 renderer in its GDI window, no
# DirectDraw. A file RENDERER beside this script holding "d3d" (or "software") does the same
# without touching Steam's launch options. The exe reads the choice from game/system/HELLBEND.INI [Retrodeck]
# Direct3D (1 / 0), written here.
RENDERER="${RENDERER:-}"
[ -z "$RENDERER" ] && [ -s "$HERE/RENDERER" ] && RENDERER="$(head -1 "$HERE/RENDERER" | tr -d ' \r\n')"
RENDERER="${RENDERER:-d3d}"
case "$RENDERER" in
  software) OVR="winmm=n,b;ddraw=b;d3dimm=b"; D3D=0 ;;
  *)   RENDERER=d3d; OVR="winmm=n,b;ddraw=n,b;d3dimm=n,b"; D3D=1 ;;
esac
export WINEDLLOVERRIDES="${OVR}${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
log "RENDERER=$RENDERER WINEDLLOVERRIDES=$WINEDLLOVERRIDES"
python3 - "$HERE/game/system/HELLBEND.INI" "$D3D" <<'EOF' >>"$LOG" 2>&1 || log "WARNING: could not set [Retrodeck] Direct3D"
import re, sys
p, v = sys.argv[1], sys.argv[2]
s = open(p, 'rb').read().decode('latin-1')
if re.search(r'(?m)^Direct3D=.*$', s):
    s = re.sub(r'(?m)^Direct3D=[^\r\n]*', 'Direct3D=' + v, s)
elif '[Retrodeck]' in s:
    s = s.replace('[Retrodeck]\r\n', '[Retrodeck]\r\nDirect3D=' + v + '\r\n', 1)
else:
    s = s.rstrip('\r\n\x1a') + '\r\n\r\n[Retrodeck]\r\nDirect3D=' + v + '\r\n'
open(p, 'wb').write(s.encode('latin-1'))
print('[Retrodeck] Direct3D=' + v)
EOF

# Wine's X input method off: HKCU\Software\Wine\X11 Driver UseXIM=N in the prefix (user.reg, edited before Wine starts;
# the game needs no input method for typing). Under old-style 32-bit Proton the game died in libX11's XFilterEvent (the input method's per-window
# filter list holding a freed entry, then "malloc(): corrupted top size") just after the Quick Configuration box
# closed; with no input method there are no such filters.
PFX="${STEAM_COMPAT_DATA_PATH:-}/pfx"
if [ -f "$PFX/user.reg" ]; then
  python3 - "$PFX/user.reg" <<'PYEOF' >>"$LOG" 2>&1 || log "WARNING: could not set UseXIM"
import sys
p = sys.argv[1]
lines = open(p, encoding='utf-8', errors='surrogateescape').read().split('\n')
head = '[Software\\\\Wine\\\\X11 Driver]'
i = next((k for k, l in enumerate(lines) if l.startswith(head)), None)
if i is None:
    lines[-1:-1] = ['', head + ' 0', '"UseXIM"="N"']
    print('UseXIM=N (new key)')
else:
    j = i + 1
    while j < len(lines) and lines[j] and not lines[j].startswith('[') and not lines[j].startswith('"UseXIM"='):
        j += 1
    if j < len(lines) and lines[j].startswith('"UseXIM"='):
        lines[j] = '"UseXIM"="N"'
        print('UseXIM=N (set)')
    else:
        k = i + 1
        while k < len(lines) and lines[k].startswith('#'):
            k += 1
        lines.insert(k, '"UseXIM"="N"')
        print('UseXIM=N (added)')
open(p, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(lines))
PYEOF
fi

# Debugging: if a file named PROTON_LOG exists beside this script, Proton writes steam-<appid>.log here. A file
# WINEDEBUG beside it adds Wine debug channels (e.g. +mci,+xinput,+seh,+win). Create / delete them from Desktop Mode.
if [ -e "$HERE/PROTON_LOG" ]; then
  export PROTON_LOG=1 PROTON_LOG_DIR="$HERE"
  log "PROTON_LOG on -> $HERE/steam-*.log"
  if [ -s "$HERE/WINEDEBUG" ]; then
    export WINEDEBUG="+timestamp,+tid,+loaddll,$(tr -d ' \n' < "$HERE/WINEDEBUG")"
  else
    # not Proton's default (+seh,+unwind ...): a fault repeating in a loop once wrote 700 MB per run
    export WINEDEBUG="+timestamp,+tid,+loaddll"
  fi
  log "WINEDEBUG=$WINEDEBUG"
fi

for f in HELLBEND.EXE SMACKW32.DLL winmm.dll winmm.ini ddraw.dll d3dimm.dll dgVoodoo.conf system/HELLBEND.INI system/GAME.POD system/STARTUP.POD \
         system/Story/Intro.smk Music/Track02.ogg; do
  [ -e "$HERE/game/$f" ] || log "WARNING: game/$f missing"
done

# Testing another Proton without touching Steam's settings: a file PROTON_VERSION beside this script holding a folder
# name from steamapps/common (e.g. "Proton 11.0") replaces the Proton in Steam's command line.
if [ -s "$HERE/PROTON_VERSION" ]; then
  want="$(head -1 "$HERE/PROTON_VERSION")"; args=()
  for a in "$@"; do
    case "$a" in */steamapps/common/*/proton) a="${a%/steamapps/common/*}/steamapps/common/$want/proton";; esac
    args+=("$a")
  done
  set -- "${args[@]}"
  log "PROTON_VERSION=$want"
fi

# Always PROTON_USE_WOW64=1, Wine's new WoW64 mode (the 32-bit game over 64-bit Wine: libX11 and the rest of the
# Linux side above 4 GB, out of reach of anything the 32-bit side writes; docs/TECHNICAL.md "Proton"). Proton 11.0 honours it (Proton 9.0 ignores it). A file NOWOW64 beside this script turns it off.
if [ ! -e "$HERE/NOWOW64" ]; then
  export PROTON_USE_WOW64=1
  log "PROTON_USE_WOW64=1"
fi

log "exec: $*"
exec "$@"
