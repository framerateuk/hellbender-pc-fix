# How it works

Notes on Hellbender (Terminal Reality / Microsoft, 1996), the US / English CD, `HELLBEND.EXE`
version 1.01 (1,685,504 bytes, linked 4 September 1996, MD5 `69ffdf565acef74fc82170a7b1fab907`).
Addresses are virtual addresses in that exe.

## The disc and Setup

Track 1 is the data track; tracks 2-9 are the game's CD music. No copy protection and no CD check:
the game opens its data through paths in `system\HELLBEND.INI`.

Setup (Microsoft ACME Setup) copied, for a Typical install with the movies: `HELLBEND.EXE`,
`SMACKW32.DLL` (RAD's Smacker player), `HELLBEND.HLP`, `readme.doc`, `system\` (the INI, `HELLBEND.INF`,
`STARTUP.POD`, `GAME.POD`, the DirectPlay service providers, `Story\*.SMK` movies) and `Sound\` (the
multiplayer taunts), and wrote registry entries the game never reads. `build.py` copies the same
files. Left out: Setup, the DirectX 3 redistributable, `Goodies\` (Internet Explorer 2.0, 1996
joystick files) and the autorun files.

## How the game works

- **An MFC 4 MDI program** for Windows 95 and NT, sorted by `GetVersion` (0x4399ae). Modern Windows
  and Wine are NT. The game starts with the **Quick Configuration** box (New Game, Multiplayer,
  Restore Game, Demo, Main Menu, Close); pause and the (Y/N) prompts are drawn in the game's own
  picture; the Settings, file and High Score boxes are Windows dialog boxes.
- **Graphics.** Software rendering into an 8-bit DIB section at 320x200, 320x400 or 640x480, shown
  with `StretchBlt` (0x438620). Full screen was DirectDraw exclusive mode (0x4022b0), on NT only at
  640x480 (0x43a971). "Use Hardware Accelerator" (`useDirect3D`) is Direct3D 3 (`IDirect3D`,
  execute buffers) at 640x480x16, only in that full screen.
- **Timing:** `timeGetTime` after `timeBeginPeriod(1)`; movement follows the clock; every loop draws
  through 0x46f300 with no limit, and the message pump (0x43a2a0) never waits.
- **Input:** the keyboard into a scan-code table (`PreTranslateMessage`, 0x43ba10), every key set in
  the INI. The joystick through winmm `joyGetPosEx` (0x45bf90); on NT the set-up (0x45bde0) forced
  it off and the reads returned at once.
- **Sound:** its own mixer thread on `waveOut`. **Music:** MCI `cdaudio` (`mciSendCommand`,
  0x44b4b0...): play track n to n+1 with notify, start again on `MCI_NOTIFY_SUCCESSFUL`.
  **Movies:** Smacker, 320x240 at 15 fps, zoomed to the view.
- **Memory check:** `GlobalMemoryStatus` (0x439fd3): `dwTotalPhys` compared *signed* with 9 MB,
  free memory plus page file with 16 MB.

## The patches

`patch_exe.py` adds a section `.rdeck` (VA 0x8f2000, 8 KB, at the end of the file) holding the new
code from `caves.s`, and redirects these sites into it. Its header lists each site.

| Patch | Was | Now |
|---|---|---|
| `ram` | `GlobalMemoryStatus` figures read signed or added; Proton's large-address-aware flag reports up to 4 GB | Every figure clamped to 2 GB - 1 |
| `renderer` | DirectDraw / Direct3D set up per `useDirect3D` | `[Retrodeck] Direct3D=1`: `useDirect3D`, full screen and 640x480 forced on, then the set-up (dgVoodoo2 underneath); `0`: no DirectDraw at all, the GDI window; missing: the game's own `useDirect3D` decides, with full screen at 640x480 when it's on |
| `window` | A captioned window with a menu bar, 640x480 client | A `WS_POPUP` covering the screen; the game's view the largest 4:3 box, centred, the rest black; no menu bar, no pointer |
| `pump` | (the pump) | The sunken edges off; the pad read; 2 ms asleep when a dialog box is up, the game is in the background or a movie plays |
| `idle` | After a game the bare window waited for its menu bar | Quick Configuration again; `Sleep(5)` in the background loop |
| `framecap` | Every loop drew as fast as the CPU allowed | At most 60 frames a second (in the Direct3D full screen dgVoodoo's `FPSLimit = 60` paces the flips) |
| `keywait` | "Wait for a key" spun on the pump | Pump, `Sleep(5)`; pad A = Y, B = N |
| `keys` | (`PreTranslateMessage`) | Enter / Esc / Space end a movie (only a mouse click did); Enter in flight = pause; Enter at a (Y/N) prompt = Y; F11 = Save Game, F12 = Resume Game |
| `quicksave` | Save Game with no file yet: the Save As box | `data\QUICK.HEL` |
| `mainmenu` | Quick Configuration's Main Menu left the bare window for its menu bar | Opens Options > Settings, then Quick Configuration again; also F9, and Y while paused |
| `joyinit`, `joyread` | Joystick off on NT | Analogue joystick mode with fixed calibration, fed from XInput every frame by `padupdate` (axes, the hat, and the game's function keys) |
| `joydevs` | `joyGetNumDevs` 0 greyed out the control choice | 16 |

`padupdate` reads the first XInput pad (`xinput1_4`, `1_3` or `9_1_0`) and posts Start / Back to
the window as Enter / Esc. The INI section is called `[Retrodeck]` because the name is a string in
the patched exe.

## Picture

**Direct3D.** The game's Direct3D 3 renderer (Gouraud shading, bilinear filtering, 16-bit at
640x480) runs only inside its DirectDraw exclusive full screen. dgVoodoo2 2.79.3 (`ddraw.dll`,
`d3dimm.dll`) provides both: `Resolution = 2x` (3D drawn at 1280x960), `ScalingMode =
stretched_ar` (4:3 with bars), `FPSLimit = 60`, 32-bit internal rendering (no 16-bit banding). The
game asks for a HAL device with perspective correction, Gouraud shading and vertex fog; dgVoodoo
reports and draws all of it. Polygon sorting errors and a scrappy radar were there on 1996 cards
too. The cockpit, HUD and text are drawn by locking the back buffer each frame, which dgVoodoo
scales with the 3D. The game's dialog boxes leave the full screen and come back (`RestoreDisplayMode`
/ `SetCooperativeLevel`); dgVoodoo only fakes those mode changes.

**Software.** The game's own renderer at 640x480 (its largest software resolution; its "custom"
mode crashes at higher ones), shown nearest-pixel in the 4:3 box.

On Windows the `--windows` INI has no `[Retrodeck] Direct3D` and `useDirect3D=1`, so the game starts
in Direct3D and its own Settings box switches. A fixed `Direct3D=0` there (an earlier version)
forced software at every start, so ticking the box never stuck.

## Proton

Under old-style 32-bit Proton (9.0 and earlier) the game crashed in libX11 after a while, the
untouched exe included: libX11's `Display` data being overwritten (`XFilterEvent`, then
`XCheckIfEvent` in a loop, "malloc(): corrupted top size"). There the Linux heap sits in the same
4 GB as the 32-bit game. Proton 11.0 with `PROTON_USE_WOW64=1` (`WINEARCH=wow64`) runs the 32-bit
game over 64-bit Wine, so the Linux side lives above 4 GB, out of reach; it has run cleanly since.
The launch script also turns Wine's X input method off (`UseXIM=N`), where the first crash was.

## ogg-winmm

ogg-winmm v2025.01.16 answers the string command "open cdaudio" by passing `MCI_OPEN` on to the
real winmm with a NULL parameter block. Windows' winmm fails and the result is ignored; Wine's
writes the device ID back through the NULL pointer, an access violation inside `winmm.dll`.
`oggwinmm_fix.py` replaces that one call with `add esp,0x10 ; xor eax,eax` (the same stack, result 0).
