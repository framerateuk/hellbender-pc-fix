# Hellbender (PC, 1996) on modern PCs and the Steam Deck

## Why this exists

I was a big fan of Terminal Velocity, and like Fury3, Hellbender is more of that, this time with
3D acceleration, which looked great. I think my copy came bundled with a Microsoft SideWinder 3D
joystick. The Windows 95 version doesn't run properly on anything newer: no joystick, no full
screen, and its Direct3D mode needs a 1996 graphics card. This kit sorts that out, so it can be
played again.

## What this does

Turns **your own** Hellbender CD into a folder that runs on the Steam Deck (Proton) or on Windows
10/11, with no installer and no registry entries:

- **Copied straight from the CD**: what the 1996 Setup installed, without running Setup.
- **The game's Direct3D renderer** ("Use Hardware Accelerator") through dgVoodoo2, drawn at 2x
  (1280x960) and full screen 4:3 with black bars. The game's own 640x480 software renderer is still
  there as the alternative.
- **CD soundtrack** from OGG files ripped from your disc.
- **Gamepad**: the game switched its joystick off on Windows NT, which modern Windows and Proton
  are. The exe now reads an Xbox-style pad (the Steam Deck's included) directly, as an analogue
  flight stick with weapons, views and the hat. The game's Settings pages are reachable from the
  pad too.
- **At most 60 frames a second, no busy waits**: it no longer runs one CPU core flat out.
- **Smaller fixes**: no window frame, menu bar or pointer; a memory check that misread modern
  amounts of RAM; quick save / resume keys; Enter pauses.

**No game files are in this repository.** Everything from the game comes from your disc when you
run `build.py`.

## What you need

| | |
|---|---|
| The game | The **Hellbender CD** (Microsoft / Terminal Reality, 1996, version 1.01, the US / English release) as `.cue` + `.bin` or CloneCD `.ccd` + `.img`, with its 8 audio tracks. `build.py` checks the exe and the game data and stops on another version. |
| Python | 3.8 or newer (python.org on Windows; already on macOS/Linux). |
| An OGG encoder | `oggenc` (vorbis-tools; Windows builds at rarewares.org) or `ffmpeg`, on the PATH. |
| dgVoodoo2 **2.79.3** | by Dege: [GitHub release v2.79.3](https://github.com/dege-diosg/dgVoodoo2/releases/tag/v2.79.3). Use 2.79.3: newer versions don't start under Wine/Proton. Keep the zip as downloaded. |
| ogg-winmm **v2025.01.16** | by AyuanX: [GitHub releases](https://github.com/ayuanx/ogg-winmm/releases). This exact release: `build.py` patches one call in its `winmm.dll` (below) and checks the file first. Keep the zip as downloaded. |

## Build

For the Steam Deck:

```
python3 build.py Hellbender.ccd --dgvoodoo dgVoodoo2_79_3.zip --ogg-winmm ogg-winmm_binary.zip
```

creates `Hellbender/` with `game/` and `hellbender_launch.sh`, in under a minute.

For Windows, add `--windows`: no launch script, and the game's own "Use Hardware Accelerator" box
(in the Settings) picks the renderer, on at first. On the Deck the launch script picks it instead
(below). `--out DIR` puts the result somewhere else. The disc's original exe and settings file are
kept in `game/_spare/`.

## Play on the Steam Deck

1. Copy `Hellbender/` to the Deck, for example to `/home/deck/Games/Hellbender/`.
2. Desktop Mode: Steam > Add a Non-Steam Game > Browse > `.../Hellbender/game/HELLBEND.EXE`.
   Rename the shortcut "Hellbender".
3. Properties > Compatibility: force **Proton 11.0**. Older Proton versions crash after a while
   (`docs/TECHNICAL.md`, "Proton"); the launch script switches on Proton 11's WoW64 mode, which
   avoids it.
4. Properties > Launch Options:
   ```
   /home/deck/Games/Hellbender/hellbender_launch.sh %command%
   ```
5. Controller layout: the standard **Gamepad** layout works, since the game reads the pad itself
   (Start and View send Enter and Esc). Worth adding in Steam's controller settings: **L4 = F11**
   (save), **R4 = F12** (resume), **L5 = C** (cloak), **R5 = N** (navigation computer), and the
   **right trackpad as a mouse** for the game's Windows dialog boxes ("Gamepad with Mouse Trackpad"
   has it).

Renderer on the Deck: Direct3D by default. For the software renderer put `RENDERER=software` before
the script path in the launch options, or a file named `RENDERER` holding `software` beside the
script.

## Play on Windows

Build with `--windows`, then run `game/HELLBEND.EXE`. A shortcut must start in the `game` folder.
To switch renderer: the Settings (Quick Configuration's Main Menu, Y on the pad while paused, or
F9) > "Use Hardware Accelerator", then quit and start again.

## Controls

| Pad | Does | Keyboard |
|---|---|---|
| Left stick | fly (analogue; pushed up = nose down, like a 1996 flight stick) | arrows |
| RT or A | fire | Space |
| LT | afterburner | F |
| Right stick up / down | throttle up / down | Z / X |
| Right stick left / right | roll | Home / Page Up |
| RB / LB | next / previous weapon | = / - (or 1-0, `) |
| D-pad | look forward / back / left / right | Ins, Del, keypad |
| Y | change views (cockpit, chase, outside); while paused: the Settings | O |
| X | instruments | I |
| B | missile target | V |
| R3 / L3 | map / crosshair | M / T |
| Start | Quick Configuration: new game; boxes: OK / Yes; in flight: pause; (Y/N): yes; movies: skip | Enter |
| View / Back | in flight: "End without saving? (Y/N)"; Quick Configuration: quit; boxes: Cancel / No | Esc |
| L4 / R4 (Deck, see above) | save / resume a saved game | F11 / F12 |
| L5 / R5 (Deck, see above) | cloak / navigation computer | C / N |

Also on the keyboard: B beacon, L headlight, Tab choose objective, [ / ] map zoom, , / . energy to
weapons / shields, P or F3 pause, F9 Settings, Ctrl+S / Ctrl+R save / resume, Ctrl+M mute, F1 help
(needs WinHelp, which Windows 10/11 no longer have).

## Settings

Everything is in `game/system/HELLBEND.INI` (the game writes it back when it quits), and the game's
own Settings pages open from Quick Configuration's Main Menu, Y while paused, or F9. The kit's copy
differs from the disc's: 640x480 (the highest resolution), the pad on, no "256 colours" box, the
movie path, and a `[Retrodeck]` section the patched exe reads:

- `PadInvertY=1`: pushing the stick up climbs instead.
- `Direct3D=1` / `0`: Direct3D or software at every start. The Deck's launch script writes it;
  without it (the Windows build) the game's "Use Hardware Accelerator" box decides.

Saved games (`*.HEL`; F11 writes `QUICK.HEL` until you resume another file) and high scores go in
`game/data/`. Music level: `CDDAVolume` in `game/winmm.ini`, or `[Sound] redbookFlag=0` in the INI
for the game's synthesized music instead of the CD tracks.

## Troubleshooting

- *The game freezes or crashes after a while on the Deck*: check the shortcut is on Proton 11.0
  and that `launch.log` says `PROTON_USE_WOW64=1`.
- *No music*: on the Deck `launch.log` must show `WINEDLLOVERRIDES=winmm=n,b;...` (no log: the
  launch option is missing `%command%`), and `game/Music/Track02.ogg` must exist.
- *A small window with a menu bar*: you're running the unpatched exe from `_spare/`.
- *Polygons drawn in the wrong order, a scrappy radar in Direct3D*: the game's own Direct3D did that
  on 1996 cards too; dgVoodoo can't change it.
- *Judder on a G-Sync / FreeSync monitor*: turn variable refresh off for this game.

## What's in this repository

| File | What |
|---|---|
| `build.py` | Builds the folder: copies the CD's game files, patches the exe, rips the soundtrack, adds the wrappers and settings. Python standard library only. |
| `patch_exe.py` | The exe patches, each explained; adds a code section to the exe. Also runs on its own. |
| `caves.s` | The new code's source (x86 assembly). `python3 patch_exe.py --check-caves` re-assembles it with clang and checks it against the bytes in `patch_exe.py`. |
| `oggwinmm_fix.py` | A 5-byte fix to ogg-winmm v2025.01.16 (its "open cdaudio" string command crashes under Wine). |
| `disc.py` | Reads the CD image: `.cue`/`.bin` or `.ccd`/`.img`, ISO 9660 and audio tracks. |
| `config/`, `config-windows/` | The game's settings for each build, dgVoodoo2's and ogg-winmm's. |
| `steamdeck/hellbender_launch.sh` | Proton launch wrapper: DLL overrides, renderer, WoW64. |
| `docs/TECHNICAL.md` | How the game works and what each patch does. |

## Credits

- **Terminal Reality** made Hellbender on its Terminal Velocity engine; **Microsoft** published it.
  Please own the game: this kit needs your disc.
- **Dege**: dgVoodoo2. **AyuanX**: ogg-winmm.

## License

The scripts and docs in this repository: MIT (see `LICENSE`). The license covers only this
repository's own files, not the game, dgVoodoo2 or ogg-winmm.

Not affiliated with or endorsed by the game's rights holders.
