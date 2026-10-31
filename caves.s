# Hellbender (Terminal Reality / Microsoft, 1996; HELLBEND.EXE v1.01 of the US retail disc, 1,685,504 bytes, linked 4 Sep
# 1996): new code for patch_exe.py. It goes into a section patch_exe.py adds to the exe, ".rdeck" at VA 0x8f2000 (file
# offset 0x19b800, the end of the file, after the linker's 60 KB of debug data that follows .reloc; 0x2000 bytes,
# readable / writable / executable): this code from 0x8f2000, its variables from 0x8f3000 (zero when the exe loads).
# The exe always loads at its 0x400000 base (no dynamic-base flag; the patch also marks it "relocations stripped"), so
# absolute addresses are used throughout.
#
# Assembled with Apple clang (integrated assembler):
#   clang -target i386-pc-linux-gnu -c caves.s -o caves.o
# patch_exe.py carries the resulting bytes (CAVE) and checks them against this file when clang is around
# (patch_exe.py --check-caves). docs/TECHNICAL.md explains each routine.
#
# Rule kept from Speedster (23 Oct 2026): never keep a value in ecx / edx across an API call (Proton's timeGetTime
# and friends change them). Values live in ebx / esi / edi or memory across calls.
.intel_syntax noprefix
.set BASE, 0x8f2000

# imports used (IAT slots of HELLBEND.EXE v1.01)
.set Sleep,                 0x879d0c
.set timeGetTime,           0x87a08c
.set LoadLibraryA,          0x879d28
.set GetProcAddress,        0x879d2c
.set GlobalMemoryStatus,    0x879d38
.set GetPrivateProfileIntA, 0x879d60
.set lstrcpyA,              0x879d7c
.set GetWindowDC,           0x879dfc
.set SetWindowPos,          0x879f9c
.set GetWindow,             0x879fb0
.set GetParent,             0x879fb4
.set GetActiveWindow,       0x879fc4
.set PostMessageA,          0x879fd4
.set SetCursor,             0x879fe8
.set PeekMessageA,          0x879fec
.set SetWindowLongA,        0x879ffc
.set GetWindowRect,         0x87a004
.set GetWindowLongA,        0x87a038
.set GetSystemMetrics,      0x87a03c
.set ReleaseDC,             0x87a048
.set PatBlt,                0x8799bc

# game
.set MAINHWND,  0x579764             # the main (MDI frame) window, set by InitInstance
.set MSGHWND,   0x57a430             # the window the game hands to its message boxes and movie stop
.set KEYS,      0x5b36c0             # the keyboard: one byte per scan code, 1 = down (PreTranslateMessage 0x43ba10)
.set INGAME,    0x5126ac             # 1 while a game is in progress
.set MOVIE,     0x512d64             # 1 while a Smacker movie plays
.set INIPATH,   0x502ab0             # ".\system\hellbend.ini"
.set JOYMODE,   0x512578             # joystickActive: 0 keyboard, 1 gamepad (digital), 2 joystick, 3 with throttle
.set JOYX,      0x5b3660             # the joystick read's X / Y / Z / R and buttons (0x45bf90)
.set JOYY,      0x5b366c
.set JOYZ,      0x59d140
.set JOYR,      0x59d104
.set JOYBTN,    0x5b3a10
.set HATUP,     0x512728             # the hat (dwPOV 0 / 9000 / 18000 / 27000): 1 = pushed that way
.set HATRIGHT,  0x512734
.set HATDOWN,   0x51272c
.set HATLEFT,   0x512730
.set XMIN,      0x5b3674             # calibration (joyGetDevCaps in the original set-up 0x45bde0)
.set XMAX,      0x59d350
.set YMIN,      0x5b3800
.set YMAX,      0x59d1fc
.set ZMIN,      0x59cff0
.set ZMAX,      0x5b367c
.set RMIN,      0x59d12c
.set RMAX,      0x59d128
.set XCEN,      0x5b36a0
.set YCEN,      0x5b388c
.set RCEN,      0x5b3820
.set XYQ,       0x51257c
.set RHALF,     0x59d124
.set NBUTTONS,  0x5129c4
.set HASRUDDER, 0x512580
.set RUDDERON,  0x5b39e8
.set DEADZONE,  0x512748             # useJoystickDeadZone (the pad code has its own)
.set STOPMOVIE, 0x49f660             # cdecl (hwnd): end the Smacker movie that plays
.set PUSHKEY,   0x46f2a0             # cdecl (char): put a typed key into the "wait for a key" queue
.set PUMP1,     0x46f360             # one pass of the message pump
.set QUIT,      0x512634             # 1 once the game is to end
.set USED3D,    0x500224             # useDirect3D (Settings: "Use Hardware Accelerator")
.set AUTOFS,    0x50d778             # autoFullScreen (Quick Configuration: Full Screen)
.set PREFDISP,  0x50d774             # preferredDisplay: 0 320x200, 1 320x400, 2 640x480
.set DDFULL,    0x50d760             # 1 while the DirectDraw full screen is on
.set PAUSED,    0x50f58c             # 1 while a game is paused (P / F3; "Paused--F3 to resume.")
.set DDINIT,    0x402160             # the DirectDraw / Direct3D set-up (eax = 1 when DirectDraw is there)

# our variables (.rdeck from 0x8f3000, zero at load)
.set XGS,     0x8f3000               # XInputGetState (0 = no XInput DLL)
.set XINIT,   0x8f3004               # 1 once readpad has looked for XInput
.set PB,      0x8f3008               # the pad as readpad last read it: XInput wButtons
.set PLX,     0x8f300c               #   left stick X / Y (signed, up +)
.set PLY,     0x8f3010
.set PRX,     0x8f3014               #   right stick X / Y
.set PRY,     0x8f3018
.set PLT,     0x8f301c               #   left / right trigger 0..255
.set PRT,     0x8f3020
.set PPREV,   0x8f3024               # wButtons at the previous padupdate
.set NEWP,    0x8f3028               # buttons newly down at the last padupdate
.set VPREV,   0x8f302c               # the pad functions held at the previous padupdate (bits of ftab)
.set FINIT,   0x8f3030               # framecap: 1 once started
.set FDUE3,   0x8f3034               #   the next frame's time in thirds of a millisecond
.set INVY,    0x8f3038               # HELLBEND.INI [Retrodeck] PadInvertY
.set JINIT,   0x8f303c               # 1 once joyinit ran
.set SETUP,   0x8f3040               # 1 once setupwin found the MDI client and the view
.set BOXW,     0x8f3044               # ncpaint: the 4:3 client box (width, height, left, top)
.set BOXH,     0x8f3048
.set BOXX,     0x8f304c
.set BOXY,     0x8f3050
.set INQC,     0x8f305c               # 1 while idlehook shows Quick Configuration
.set PAUSEY,   0x8f3060               # 1 while the Y that opened Settings in a paused game is held
.set INWAIT,   0x8f3054               # 1 while keywait waits for a key (a Y/N prompt, "press a key")
.set XS,      0x8f3080               # an XINPUT_STATE (16 bytes)
.set MSGBUF,  0x8f30a0               # a MSG for PeekMessage (28 bytes)

.set DZ,      7000                   # left stick dead zone (of 32768): 21 %
.set RDZ,     16000                  # right stick: a direction counts from half way out
.set TDZ,     40                     # a trigger counts from 16 % of the way in

.macro PUSHI v                       # push imm32
  .byte 0x68
  .long \v
.endm
.macro JMPA t                        # jmp to an absolute address in the exe
  .byte 0xe9
  .long \t - (BASE + (. + 4 - start))
.endm
.macro CALLA t                       # call an absolute address in the exe
  .byte 0xe8
  .long \t - (BASE + (. + 4 - start))
.endm
.macro ADDR sym                      # the absolute address of a label of ours
  .long BASE + (\sym - start)
.endm

.text
start:

# ---------------------------------------------------------------------------------------------------------------
# memstat (patch ram): both GlobalMemoryStatus calls (0x439fd3 InitInstance: dwTotalPhys kept at 0x5126f8, compared
# signed with 9 MB at 0x41ef71 for the detail / cache size, and dwAvailPhys + dwAvailPageFile compared with 16 MB for
# the "may not function properly" box; 0x439e71: dwAvailPhys) come here, stdcall like the API. Proton marks every exe
# large-address-aware, so Wine reports up to 4 GB: read as negative, or the two added together wrap to a small
# number. Every figure of the MEMORYSTATUS is clamped to 2 GB - 1 (what Windows gives an exe without the flag).
memstat:
  push dword ptr [esp + 4]
  call dword ptr [GlobalMemoryStatus]
  mov eax, dword ptr [esp + 4]
  mov ecx, 6                         # dwTotalPhys .. dwAvailVirtual
1:
  cmp dword ptr [eax + 8], 0x7fffffff
  jbe 2f
  mov dword ptr [eax + 8], 0x7fffffff
2:
  add eax, 4
  dec ecx
  jnz 1b
  ret 4

# ---------------------------------------------------------------------------------------------------------------
# precreate (patch window): CMainFrame::PreCreateWindow (0x49ecc0) made the frame WS_POPUP | WS_CAPTION | WS_SYSMENU |
# WS_MINIMIZEBOX, 640 x 480 (a window whose client area is the 640x480 picture, with the menu bar). Now WS_POPUP |
# WS_CLIPCHILDREN, no edges, at 0, 0 the size of the screen; the game's own picture box goes inside it (ncclient).
precreate:
  push esi
  mov esi, dword ptr [esp + 8]       # CREATESTRUCT
  mov dword ptr [esi + 0x20], 0x82000000
  mov dword ptr [esi + 0x2c], 0
  push ecx
  push 0                             # SM_CXSCREEN
  call dword ptr [GetSystemMetrics]
  mov dword ptr [esi + 0x14], eax
  push 1                             # SM_CYSCREEN
  call dword ptr [GetSystemMetrics]
  mov dword ptr [esi + 0x10], eax
  pop ecx
  mov dword ptr [esi + 0x18], 0
  mov dword ptr [esi + 0x1c], 0
  push esi
  CALLA 0x4df01c                     # CMDIFrameWnd::PreCreateWindow (eax = its result, kept)
  and dword ptr [esi + 0x20], 0x0000ffff   # MFC's frame bits (FWS_...) stay, the window styles are ours
  or dword ptr [esi + 0x20], 0x82000000
  pop esi
  ret 4

# minmax (patch window): CMainFrame::OnGetMinMaxInfo (0x49ec30) pinned the frame to the size that leaves a 640x480
# client area. Now the screen is the largest size and the place a maximised frame takes.
minmax:
  push esi
  mov esi, dword ptr [esp + 8]       # MINMAXINFO
  push 0
  call dword ptr [GetSystemMetrics]
  mov dword ptr [esi + 8], eax       # ptMaxSize
  mov dword ptr [esi + 0x20], eax    # ptMaxTrackSize
  push 1
  call dword ptr [GetSystemMetrics]
  mov dword ptr [esi + 0xc], eax
  mov dword ptr [esi + 0x24], eax
  mov dword ptr [esi + 0x10], 0      # ptMaxPosition
  mov dword ptr [esi + 0x14], 0
  pop esi
  ret 4

# ---------------------------------------------------------------------------------------------------------------
# framewp (patch window): CMainFrame::WindowProc (0x49ecf0, thiscall: msg, wParam, lParam; ecx = the frame) starts
# here. The frame covers the screen; its client area (where MFC lays out the MDI client, the game's child window and
# its view, which draws the picture stretched to its own size, and where the movies are zoomed to) is made the
# largest 4:3 box in the middle, the rest black:
#   WM_NCCALCSIZE      client = the 4:3 box, centred (1066x800 on the Deck); no menu bar, no edges
#   WM_NCPAINT         the bars painted black (no menu bar drawn)
#   WM_NCACTIVATE      nothing drawn
#   WM_NCHITTEST       HTCLIENT (no menu bar to click)
#   WM_SETCURSOR       no pointer over the game (dialog boxes are windows of their own and keep theirs)
#   WM_WINDOWPOSCHANGING  any move / size of the frame becomes 0, 0, the screen's size (not when minimising)
framewp:
  mov eax, dword ptr [esp + 4]
  cmp eax, 0x83
  je ncclient
  cmp eax, 0x85
  je ncpaint
  cmp eax, 0x86
  je 1f
  cmp eax, 0x84
  je 1f
  cmp eax, 0x20
  je setcur
  cmp eax, 0x46
  je wpchanging
framewp_orig:
  push ebx                           # the instructions the jump replaced
  push esi
  mov esi, dword ptr [esp + 0xc]
  JMPA 0x49ecf6
1:
  mov eax, 1                         # WM_NCACTIVATE: TRUE, nothing drawn; WM_NCHITTEST: HTCLIENT
  ret 0xc

setcur:
  push 0
  call dword ptr [SetCursor]
  mov eax, 1
  ret 0xc

wpchanging:
  push esi
  mov esi, dword ptr [esp + 0x10]    # WINDOWPOS
  mov eax, dword ptr [esi + 0x18]
  and eax, 3                         # SWP_NOSIZE | SWP_NOMOVE: nothing to change
  cmp eax, 3
  je 9f
  cmp dword ptr [esi + 8], -32000    # minimising
  jle 9f
  push ecx
  push 0
  call dword ptr [GetSystemMetrics]
  mov dword ptr [esi + 0x10], eax
  push 1
  call dword ptr [GetSystemMetrics]
  mov dword ptr [esi + 0x14], eax
  pop ecx
  mov dword ptr [esi + 8], 0
  mov dword ptr [esi + 0xc], 0
  and dword ptr [esi + 0x18], 0xfffffffc
9:
  pop esi
  jmp framewp_orig

# fit43: eax = width, ecx = height -> eax, ecx = the largest 4:3 box inside. Uses edx.
fit43:
  push ebx
  mov ebx, eax
  lea eax, [ecx * 4]
  xor edx, edx
  push ecx
  mov ecx, 3
  div ecx                            # w = h * 4 / 3
  pop ecx
  cmp eax, ebx
  jbe 1f
  mov eax, ebx                       # narrower than 4:3: w = width, h = w * 3 / 4
  lea ecx, [ebx + ebx * 2]
  shr ecx, 2
1:
  pop ebx
  ret

ncclient:
  push ebx
  push esi
  push edi
  mov esi, dword ptr [esp + 0x18]    # the proposed window rectangle (NCCALCSIZE_PARAMS' first, or a RECT)
  mov ebx, dword ptr [esi + 8]
  sub ebx, dword ptr [esi]           # W
  mov edi, dword ptr [esi + 12]
  sub edi, dword ptr [esi + 4]       # H
  mov eax, ebx
  mov ecx, edi
  call fit43
  sub ebx, eax
  sar ebx, 1
  sub edi, ecx
  sar edi, 1
  add ebx, dword ptr [esi]
  add edi, dword ptr [esi + 4]
  mov dword ptr [esi], ebx
  mov dword ptr [esi + 4], edi
  add ebx, eax
  add edi, ecx
  mov dword ptr [esi + 8], ebx
  mov dword ptr [esi + 12], edi
  pop edi
  pop esi
  pop ebx
  xor eax, eax
  ret 0xc

ncpaint:
  push ebx
  push esi
  push edi
  push ebp
  mov ebp, dword ptr [ecx + 0x1c]    # the frame's HWND
  sub esp, 16
  mov eax, esp
  push eax
  push ebp
  call dword ptr [GetWindowRect]
  mov ebx, dword ptr [esp + 8]
  sub ebx, dword ptr [esp]           # W
  mov edi, dword ptr [esp + 12]
  sub edi, dword ptr [esp + 4]       # H
  add esp, 16
  push ebp
  call dword ptr [GetWindowDC]
  mov esi, eax
  test esi, esi
  jz 9f
  mov eax, ebx
  mov ecx, edi
  call fit43
  mov dword ptr [BOXW], eax
  mov dword ptr [BOXH], ecx
  mov edx, ebx
  sub edx, eax
  sar edx, 1
  mov dword ptr [BOXX], edx
  mov edx, edi
  sub edx, ecx
  sar edx, 1
  mov dword ptr [BOXY], edx
  push 0x42                          # BLACKNESS: left bar
  push edi
  push dword ptr [BOXX]
  push 0
  push 0
  push esi
  call dword ptr [PatBlt]
  mov eax, dword ptr [BOXX]            # right bar
  add eax, dword ptr [BOXW]
  mov edx, ebx
  sub edx, eax
  push 0x42
  push edi
  push edx
  push 0
  push eax
  push esi
  call dword ptr [PatBlt]
  push 0x42                          # top bar
  push dword ptr [BOXY]
  push ebx
  push 0
  push 0
  push esi
  call dword ptr [PatBlt]
  mov eax, dword ptr [BOXY]            # bottom bar
  add eax, dword ptr [BOXH]
  mov edx, edi
  sub edx, eax
  push 0x42
  push edx
  push ebx
  push eax
  push 0
  push esi
  call dword ptr [PatBlt]
  push esi
  push ebp
  call dword ptr [ReleaseDC]
9:
  pop ebp
  pop edi
  pop esi
  pop ebx
  xor eax, eax
  ret 0xc

# setupwin: once the MDI client and the game's view exist, their sunken edges (WS_EX_CLIENTEDGE) go, so the view is the
# whole 4:3 box (the game sizes its child window to the frame's client area, 0x49e6c0).
setupwin:
  cmp dword ptr [SETUP], 0
  jne 9f
  mov ebx, dword ptr [MAINHWND]
  test ebx, ebx
  jz 9f
  push 5                             # GW_CHILD: the MDI client
  push ebx
  call dword ptr [GetWindow]
  test eax, eax
  jz 9f
  mov esi, eax
  push 5                             # the game's MDI child
  push esi
  call dword ptr [GetWindow]
  test eax, eax
  jz 9f
  push 5                             # its view
  push eax
  call dword ptr [GetWindow]
  test eax, eax
  jz 9f
  mov edi, eax
  mov dword ptr [SETUP], 1
  push 0
  push -20                           # GWL_EXSTYLE
  push esi
  call dword ptr [SetWindowLongA]
  push 0
  push -20
  push edi
  call dword ptr [SetWindowLongA]
  push 0x37                          # SWP_FRAMECHANGED | NOACTIVATE | NOZORDER | NOMOVE | NOSIZE
  push 0
  push 0
  push 0
  push 0
  push 0
  push esi
  call dword ptr [SetWindowPos]
  push 0x37
  push 0
  push 0
  push 0
  push 0
  push 0
  push edi
  call dword ptr [SetWindowPos]
9:
  ret

# ---------------------------------------------------------------------------------------------------------------
# pumphook (patch pump): the game's message pump (CHellApp::PumpMessage 0x43a2a0: PeekMessage, never waits) is what
# every loop calls, MFC's modal dialog loop included, so its dialogs (Quick Configuration, Pause, End Game ...) kept a
# core busy. Now first: setupwin, the pad (padupdate), and when no message waits and no game is being flown (a dialog
# box is the active window, the game is in the background, a movie plays between its frames, no game) 2 ms asleep.
pumphook:
  pushad
  call setupwin
  call padupdate
  push 0                             # PM_NOREMOVE
  push 0
  push 0
  push 0
  PUSHI MSGBUF
  call dword ptr [PeekMessageA]
  test eax, eax
  jnz 9f
  cmp dword ptr [MOVIE], 0
  jne 8f
  cmp dword ptr [INGAME], 1
  jne 8f
  call dword ptr [GetActiveWindow]
  cmp eax, dword ptr [MAINHWND]
  je 9f
8:
  push 2
  call dword ptr [Sleep]
9:
  popad
  sub esp, 4                         # the instructions the jump replaced
  mov eax, dword ptr [0x53b964]
  JMPA 0x43a2a8

# idlehook (patch idle): the app's OnIdle (0x43b0b0) runs only between games (CHellApp::Run 0x439720: Quick
# Configuration once, then pump / the requested command (a game, the demo, a resume) / OnIdle). After a game ended the
# original left the bare window, its menu bar the only way on (gone here; the window stayed white). Now, with no game,
# movie, request or quit pending, Quick Configuration again (the app's own 0x455480), as at start; then OnIdle.
idlehook:
  cmp dword ptr [QUIT], 0
  jne 9f
  cmp dword ptr [INGAME], 0
  jne 9f
  cmp dword ptr [MOVIE], 0
  jne 9f
  cmp dword ptr [ecx + 0x128], 0     # a command requested, not run yet
  jne 9f
  cmp dword ptr [INQC], 0
  jne 9f
  push ecx
  mov dword ptr [INQC], 1
  mov eax, dword ptr [ecx]
  call dword ptr [eax + 0xb0]        # Quick Configuration (sets the request)
  mov dword ptr [INQC], 0
  pop ecx
9:
  mov eax, dword ptr [esp + 4]       # the instructions the jump replaced
  sub esp, 4
  JMPA 0x43b0b7

# idlepump (patch idle): with no game running (title, between the Quick Configuration box and a game) the loop at
# 0x46f392 pumped as fast as it could; now 5 ms asleep before each pass. ecx = the app (thiscall PumpMessage).
idlepump:
  push ecx
  push 5
  call dword ptr [Sleep]
  pop ecx
  mov eax, dword ptr [ecx]
  jmp dword ptr [eax + 0x60]

# framecap (patch framecap): 0x46f300 shows a frame (the app's draw, then the pump) for every loop of the game; none
# waited, the game times its movement by the clock (0x46f160, timeGetTime), so it drew as many frames as the CPU
# allowed. Now at most 60 frames a second: frame n is shown at t0 + n * 50/3 ms (kept in thirds of a millisecond,
# timeGetTime * 3, wrap-safe), sleeping 1 ms at a time until then (the game's own timeBeginPeriod(1), 0x46f0e0); more
# than 50 ms behind (a load), start again from now. Not in the DirectDraw full screen (Direct3D): there dgVoodoo's
# FPSLimit paces the flips. Then the instruction the jump replaced and on into 0x46f306.
framecap:
  cmp dword ptr [DDFULL], 0          # DirectDraw full screen: dgVoodoo's FPSLimit paces the flips
  jne 6f
  pushad
1:
  call dword ptr [timeGetTime]
  lea eax, [eax + eax * 2]
  cmp dword ptr [FINIT], 0
  jne 2f
  mov dword ptr [FINIT], 1
  mov dword ptr [FDUE3], eax
  jmp 5f
2:
  mov ecx, eax
  sub ecx, dword ptr [FDUE3]         # thirds of a ms since the frame was due (signed)
  jns 3f
  push 1
  call dword ptr [Sleep]
  jmp 1b
3:
  cmp ecx, 150
  jl 5f
  mov dword ptr [FDUE3], eax         # far behind: from now
5:
  add dword ptr [FDUE3], 50
  popad
6:
  mov ecx, dword ptr [0x5042d0]
  JMPA 0x46f306

# keywait (patch keywait): "wait for a key" (0x46f200: "End without saving? (Y/N)" after Esc, the other Y/N prompts,
# "press a key" screens) spun on the pump; now the pump, 5 ms asleep, and the pad: A = Y, B = N (Start is Enter, Back
# Esc already, from Steam Input or padupdate).
keywait:
  mov dword ptr [INWAIT], 1
  CALLA PUMP1
  mov dword ptr [INWAIT], 0
  pushad
  push 5
  call dword ptr [Sleep]
  mov eax, 0x59                      # 'Y'
  test dword ptr [NEWP], 0x1000      # A
  jnz 1f
  mov eax, 0x4e                      # 'N'
  test dword ptr [NEWP], 0x2000      # B
  jz 9f
1:
  mov dword ptr [NEWP], 0
  push eax
  CALLA PUSHKEY
  add esp, 4
9:
  popad
  ret

# ---------------------------------------------------------------------------------------------------------------
# keyfilter (patch keys): the app's PreTranslateMessage (0x43ba10, thiscall: MSG *) starts here; it is where the game
# puts keys into its key table. Before it:
#   a movie playing: Enter, Esc or Space ends it (only a mouse click did; Esc went on to "End game?")
#   Enter while a Y/N prompt waits ("End without saving? (Y/N)" after Esc): Y.
#   Enter down in a game (the game's window, not a dialog box, no movie): the P key (pause, the Pause box; Start on the
#     pad). Enter did nothing in flight. Its key up is swallowed too.
#   F9 (the game's window): Options > Settings (the property sheet the menu bar opened).
#   F11 in a game: Game > Save Game (data\QUICK.HEL when the game has no file yet, patch quicksave); F12: Game > Resume
#     Game (its file box). Steam Input puts them on L4 / R4.
keyfilter:
  pushad
  mov esi, dword ptr [esp + 0x24]    # MSG
  mov edx, dword ptr [esi + 4]
  mov ebx, dword ptr [esi + 8]       # virtual key
  cmp edx, 0x100                     # WM_KEYDOWN
  je 10f
  cmp edx, 0x101                     # WM_KEYUP
  jne 80f
  cmp ebx, 0x0d
  jne 80f
  call inflight
  test eax, eax
  jz 80f
  jmp 70f
10:
  cmp dword ptr [MOVIE], 0
  je 20f
  cmp ebx, 0x0d
  je 11f
  cmp ebx, 0x1b
  je 11f
  cmp ebx, 0x20
  jne 20f
11:
  push dword ptr [MSGHWND]
  CALLA STOPMOVIE
  add esp, 4
  jmp 70f
20:
  cmp ebx, 0x0d
  jne 30f
  cmp dword ptr [INWAIT], 0          # a Y/N prompt waits: Enter (Start) = Y
  je 21f
  push 0x59
  CALLA PUSHKEY
  add esp, 4
  jmp 70f
21:
  call inflight
  test eax, eax
  jz 80f
  mov byte ptr [KEYS + 0x19], 1      # P: pause
  jmp 70f
30:
  cmp ebx, 0x78                      # F9: Options > Settings (the game's window, any time)
  jne 31f
  call inframe
  test eax, eax
  jz 80f
  mov edi, 0x8008
  jmp 45f
31:
  mov edi, 0x803f                    # F11: Save Game
  cmp ebx, 0x7a
  je 40f
  mov edi, 0x8005                    # F12: Resume Game
  cmp ebx, 0x7b
  jne 80f
40:
  call inflight
  test eax, eax
  jz 80f
45:
  push 0
  push edi
  push 0x111                         # WM_COMMAND
  push dword ptr [MAINHWND]
  call dword ptr [PostMessageA]
70:
  popad
  mov eax, 1                         # handled: not dispatched
  ret 4
80:
  popad
  sub esp, 0x14                      # the instructions the jump replaced
  push ebx
  push esi
  JMPA 0x43ba15

# inflight: esi = a MSG; eax = 1 when a game is in progress, no movie plays and the message's window belongs to the
# game's main window (not to a dialog box); inframe: the same, game or not. Uses eax, ecx, edx.
inflight:
  cmp dword ptr [INGAME], 1
  jne 8f
inframe:                             # (the same without "a game is in progress")
  cmp dword ptr [MOVIE], 0
  jne 8f
  push edi
  mov edi, dword ptr [esi]
1:
  test edi, edi
  jz 7f
  push -16                           # GWL_STYLE
  push edi
  call dword ptr [GetWindowLongA]
  test eax, 0x40000000               # WS_CHILD: up to the parent
  jz 2f
  push edi
  call dword ptr [GetParent]
  mov edi, eax
  jmp 1b
2:
  cmp edi, dword ptr [MAINHWND]
  jne 7f
  pop edi
  mov eax, 1
  ret
7:
  pop edi
8:
  xor eax, eax
  ret

# renderer (patch renderer): InitInstance's DirectDraw / Direct3D set-up (0x43a21c: "mov esi, [useDirect3D]; call
# 0x402160"). HELLBEND.INI [Retrodeck] Direct3D (hellbender_launch.sh writes 1 or 0 from RENDERER=):
#   1  Direct3D: useDirect3D, autoFullScreen and 640x480 forced on (on NT the game's full screen is DirectDraw at
#      640x480 only, Direct3D only there; dgVoodoo2 provides both), then the set-up as before
#   0  software: no DirectDraw at all (build 1): the game's own renderer in its GDI window, autoFullScreen off
#   missing (Windows, no launch script): the game's own Settings box decides ("Use Hardware Accelerator",
#      useDirect3D, from the next start): on = 640x480 full screen as for 1; off = the set-up as the game did it
#      (DirectDraw there, the picture in the GDI window). With a fixed 0 on Windows, ticking the box never stuck.
# Returns esi = useDirect3D, eax = DirectDraw found, as the two instructions did.
renderer:
  PUSHI INIPATH
  push 2
  PUSHI BASE + (s_d3d - start)
  PUSHI BASE + (s_retrodeck - start)
  call dword ptr [GetPrivateProfileIntA]
  cmp eax, 2
  jne 2f
  mov esi, dword ptr [USED3D]
  test esi, esi
  jz 3f
  mov dword ptr [AUTOFS], 1
  mov dword ptr [PREFDISP], 2
3:
  CALLA DDINIT
  ret
2:
  test eax, eax
  jnz 1f
  mov dword ptr [USED3D], 0
  mov dword ptr [AUTOFS], 0
  xor esi, esi
  xor eax, eax
  ret
1:
  mov dword ptr [USED3D], 1
  mov dword ptr [AUTOFS], 1
  mov dword ptr [PREFDISP], 2
  mov esi, 1
  CALLA DDINIT
  ret

# mainmenu (patch mainmenu): Quick Configuration's Main Menu button (0x448a10) closed the box and left the bare window
# for its menu bar (gone). Now it posts Options > Settings (WM_COMMAND 0x8008) to the main window first: the box
# closes, the Settings property sheet opens, and when it closes Quick Configuration comes back (idlehook).
mainmenu:
  push ecx
  push 0
  push 0x8008
  push 0x111                         # WM_COMMAND
  push dword ptr [MAINHWND]
  call dword ptr [PostMessageA]
  pop ecx
  push esi                           # the instructions the jump replaced
  mov eax, dword ptr [ecx]
  mov esi, ecx
  JMPA 0x448a15

# quicksave (patch quicksave): Game > Save Game (0x44daa0) with no file name yet opened the Save As file box; now the
# name is data\QUICK.HEL (ebx = the command's object, its file name at +0x50) and the save goes on at 0x44dacc.
quicksave:
  lea eax, [ebx + 0x50]
  PUSHI BASE + (s_quick - start)
  push eax
  call dword ptr [lstrcpyA]
  lea edx, [ebx + 0x50]
  ret

# ---------------------------------------------------------------------------------------------------------------
# joyinit (patch joyinit): the joystick set-up (0x45bde0: the Quick Configuration box, the Controls page, the start
# of a game) switched the joystick off on Windows NT, which Wine is ("joystickActive" forced to keyboard, every read
# returning at once). Now always "Joystick" (2: analogue stick; throttle, rudder and buttons as keys), fed by the pad
# (padupdate) with fixed calibration: X / Y 0..65535 centred at 32767, no throttle or rudder axis, 8 buttons.
# HELLBEND.INI [Retrodeck] PadInvertY read.
joyinit:
  pushad
  mov dword ptr [JOYMODE], 2
  mov dword ptr [XMIN], 0
  mov dword ptr [XMAX], 65535
  mov dword ptr [YMIN], 0
  mov dword ptr [YMAX], 65535
  mov dword ptr [ZMIN], 0
  mov dword ptr [ZMAX], 0
  mov dword ptr [RMIN], 0
  mov dword ptr [RMAX], 0
  mov dword ptr [XCEN], 32767
  mov dword ptr [YCEN], 32767
  mov dword ptr [RCEN], 0
  mov dword ptr [XYQ], 16383
  mov dword ptr [RHALF], 0
  mov dword ptr [NBUTTONS], 8
  mov dword ptr [HASRUDDER], 0
  mov dword ptr [RUDDERON], 0
  mov dword ptr [DEADZONE], 0
  mov dword ptr [JOYX], 32767
  mov dword ptr [JOYY], 32767
  mov dword ptr [JOYZ], 0
  mov dword ptr [JOYR], 0
  mov dword ptr [JINIT], 1
  PUSHI INIPATH
  push 0
  PUSHI BASE + (s_invy - start)
  PUSHI BASE + (s_retrodeck - start)
  call dword ptr [GetPrivateProfileIntA]
  mov dword ptr [INVY], eax
  popad
  ret

# joyread (patch joyread): the joystick read (0x45bf90, and 0x45c0d0 in front of it) returned at once on NT. Now the
# pad is read (padupdate fills the joystick figures); joyinit first if nothing has run it.
joyread:
  cmp dword ptr [JINIT], 0
  jne 1f
  call joyinit
1:
  pushad
  call padupdate
  popad
  ret

# ---------------------------------------------------------------------------------------------------------------
# padupdate: the pad through XInput, as the game's joystick (mode 2) and keys. Called from the pump (every loop and
# dialog box) and from the joystick read (every frame in flight).
#   left stick        the joystick X / Y (analogue; 21 % dead zone, the rest scaled to the full range). Pushed up =
#                     nose down, as a 1996 flight stick (PadInvertY=1: pulled back)
#   D-pad             the hat: look left / right / back / forward (the game's own joystick view keys)
#   A                 joystick button 1 (the game's first button function, Fire) and Fire
#   the functions of ftab, as the keys HELLBEND.INI gives them (scan codes in the key table, held while held):
#   A / RT Fire, LT Afterburner, right stick up / down Throttle Up / Down, left / right Roll Left / Right,
#   Y Change Views, X Toggle Instruments, B Missile Target, RB / LB Next / Previous Weapon, R3 Map, L3 Crosshair
#   Y, game paused    Options > Settings (WM_COMMAND 0x8008)
#   Start / Back      Enter / Esc to the active window (on the Deck Steam Input types these two itself)
#   a movie playing   A, B, X or Y: Enter (keyfilter ends the movie)
padupdate:
  pushad
  call readpad
  test eax, eax
  jz 50f
  mov esi, dword ptr [PB]
  test esi, 0x8000                   # Y held in a paused game: Options > Settings once (not Change Views)
  jz 95f
  cmp dword ptr [INGAME], 1
  jne 97f
  cmp dword ptr [PAUSED], 0
  je 97f
  and esi, 0xffff7fff                # the rest of padupdate does not see Y
  cmp dword ptr [PAUSEY], 0
  jne 97f
  mov dword ptr [PAUSEY], 1
  push 0
  push 0x8008
  push 0x111                         # WM_COMMAND
  push dword ptr [MAINHWND]
  call dword ptr [PostMessageA]
  jmp 97f
95:
  mov dword ptr [PAUSEY], 0
97:
  # left stick -> joystick X / Y
  mov eax, dword ptr [PLX]
  call axis
  lea eax, [ecx + 32767]
  mov dword ptr [JOYX], eax
  mov eax, dword ptr [PLY]
  call axis
  cmp dword ptr [INVY], 0
  jne 1f
  neg ecx                            # up (+) = small Y = stick forward
1:
  lea eax, [ecx + 32767]
  mov dword ptr [JOYY], eax
  # button 1 = A (only; other bits together would read as the old 4-button hat codes 3 / 7 / 11 / 15)
  mov eax, esi
  shr eax, 12
  and eax, 1
  mov dword ptr [JOYBTN], eax
  # hat from the D-pad (XInput 1 up, 2 down, 4 left, 8 right)
  mov eax, esi
  and eax, 1
  mov dword ptr [HATUP], eax
  mov eax, esi
  shr eax, 1
  and eax, 1
  mov dword ptr [HATDOWN], eax
  mov eax, esi
  shr eax, 2
  and eax, 1
  mov dword ptr [HATLEFT], eax
  mov eax, esi
  shr eax, 3
  and eax, 1
  mov dword ptr [HATRIGHT], eax
  # the pad functions held now -> edi (bits in ftab order)
  xor edi, edi
  test esi, 0x1000                   # A
  jnz 2f
  cmp dword ptr [PRT], TDZ           # RT
  jb 3f
2:
  or edi, 1                          # Fire
3:
  cmp dword ptr [PLT], TDZ           # LT
  jb 4f
  or edi, 2                          # Afterburner
4:
  mov eax, dword ptr [PRY]
  cmp eax, RDZ
  jl 5f
  or edi, 4                          # Throttle Up
5:
  cmp eax, -RDZ
  jg 6f
  or edi, 8                          # Throttle Down
6:
  mov eax, dword ptr [PRX]
  cmp eax, -RDZ
  jg 7f
  or edi, 0x10                       # Roll Left
7:
  cmp eax, RDZ
  jl 8f
  or edi, 0x20                       # Roll Right
8:
  .byte 0xbb                         # mov ebx, btab: (XInput button, function bit) pairs
  ADDR btab
9:
  movzx eax, word ptr [ebx]
  test eax, eax
  jz 10f
  test esi, eax
  jz 91f
  movzx eax, word ptr [ebx + 2]
  or edi, eax
91:
  add ebx, 4
  jmp 9b
10:
  # pressed / released since the last call -> the key table
  mov edx, dword ptr [VPREV]
  mov dword ptr [VPREV], edi
  mov eax, edx
  not eax
  and eax, edi                       # newly held
  not edi
  and edi, edx                       # newly let go
  mov edx, eax
  .byte 0xbb                         # mov ebx, ftab
  ADDR ftab
  mov ecx, 1
11:
  mov eax, dword ptr [ebx]
  test eax, eax
  jz 15f
  mov eax, dword ptr [eax]           # the function's key (scan code) from HELLBEND.INI
  and eax, 0xff
  test edx, ecx
  jz 12f
  mov byte ptr [KEYS + eax], 1
12:
  test edi, ecx
  jz 13f
  mov byte ptr [KEYS + eax], 0
13:
  add ebx, 4
  shl ecx, 1
  jmp 11b
15:
  # button edges
  mov edi, dword ptr [PPREV]
  mov dword ptr [PPREV], esi
  mov eax, edi
  not eax
  and eax, esi
  mov dword ptr [NEWP], eax
  mov ebx, eax
  cmp dword ptr [MOVIE], 0
  je 20f
  test ebx, 0xf000                   # A B X Y during a movie: Enter
  jz 20f
  push 0x001c0001
  push 0x0d
  push 0x100
  push dword ptr [MAINHWND]
  call dword ptr [PostMessageA]
20:
  test ebx, 0x10                     # Start: Enter
  jz 21f
  mov edi, 0x0d
  mov esi, 0x001c0001
  call postkey
21:
  test ebx, 0x20                     # Back: Esc
  jz 22f
  mov edi, 0x1b
  mov esi, 0x00010001
  call postkey
22:
  popad
  ret
50:
  # no pad: the joystick centred, no buttons, every pad function let go
  mov dword ptr [JOYX], 32767
  mov dword ptr [JOYY], 32767
  mov dword ptr [JOYBTN], 0
  mov dword ptr [HATUP], 0
  mov dword ptr [HATDOWN], 0
  mov dword ptr [HATLEFT], 0
  mov dword ptr [HATRIGHT], 0
  mov edi, dword ptr [VPREV]
  .byte 0xbb                         # mov ebx, ftab
  ADDR ftab
  mov ecx, 1
51:
  mov eax, dword ptr [ebx]
  test eax, eax
  jz 52f
  test edi, ecx
  jz 53f
  mov eax, dword ptr [eax]
  and eax, 0xff
  mov byte ptr [KEYS + eax], 0
53:
  add ebx, 4
  shl ecx, 1
  jmp 51b
52:
  mov dword ptr [VPREV], 0
  mov dword ptr [PPREV], 0
  mov dword ptr [NEWP], 0
  popad
  ret

# postkey: edi = a virtual key, esi = its lParam: key down and up posted to the active window (a dialog box or the
# game). Uses eax, ecx, edx, ebp.
postkey:
  call dword ptr [GetActiveWindow]
  test eax, eax
  jnz 1f
  mov eax, dword ptr [MAINHWND]
1:
  mov ebp, eax
  push esi
  push edi
  push 0x100                         # WM_KEYDOWN
  push ebp
  call dword ptr [PostMessageA]
  mov eax, esi
  or eax, 0xc0000000
  push eax
  push edi
  push 0x101                         # WM_KEYUP
  push ebp
  call dword ptr [PostMessageA]
  ret

# axis: eax = a stick axis (-32768..32767) -> ecx = -32767..32767 with the dead zone DZ cut out and the rest scaled
# to the full range. Uses eax, ecx, edx.
axis:
  mov ecx, eax
  sar ecx, 31                        # -1 if negative
  xor eax, ecx
  sub eax, ecx                       # |v|
  sub eax, DZ
  jg 1f
  xor ecx, ecx
  ret
1:
  push ecx
  imul eax, eax, 32767
  xor edx, edx
  push ebx
  mov ebx, 32768 - DZ
  div ebx
  pop ebx
  cmp eax, 32767
  jbe 2f
  mov eax, 32767
2:
  pop ecx
  xor eax, ecx                       # the sign back
  sub eax, ecx
  mov ecx, eax
  ret

# readpad: XInputGetState of the first connected pad (xinput1_4, 1_3 or 9_1_0, whichever loads) -> PB, PLX, PLY,
# PRX, PRY, PLT, PRT; eax = 1, or 0 with them zeroed when there is no pad (or no XInput).
readpad:
  pushad
  cmp dword ptr [XINIT], 0
  jne 10f
  mov dword ptr [XINIT], 1
  .byte 0xbe                         # mov esi, the three names (16 bytes each)
  ADDR s_xinput
  mov ebx, 3
2:
  push esi
  call dword ptr [LoadLibraryA]
  test eax, eax
  jz 3f
  PUSHI BASE + (s_xgs - start)
  push eax
  call dword ptr [GetProcAddress]
  test eax, eax
  jz 3f
  mov dword ptr [XGS], eax
  jmp 10f
3:
  add esi, 16
  dec ebx
  jnz 2b
10:
  cmp dword ptr [XGS], 0
  je 99f
  xor ebx, ebx                       # pad index
11:
  PUSHI XS
  push ebx
  call dword ptr [XGS]
  test eax, eax
  jz 12f
  inc ebx
  cmp ebx, 4
  jb 11b
  jmp 99f
12:
  movzx eax, word ptr [XS + 4]
  mov dword ptr [PB], eax
  movzx eax, byte ptr [XS + 6]
  mov dword ptr [PLT], eax
  movzx eax, byte ptr [XS + 7]
  mov dword ptr [PRT], eax
  movsx eax, word ptr [XS + 8]
  mov dword ptr [PLX], eax
  movsx eax, word ptr [XS + 10]
  mov dword ptr [PLY], eax
  movsx eax, word ptr [XS + 12]
  mov dword ptr [PRX], eax
  movsx eax, word ptr [XS + 14]
  mov dword ptr [PRY], eax
  popad
  mov eax, 1
  ret
99:
  xor eax, eax
  mov dword ptr [PB], eax
  mov dword ptr [PLX], eax
  mov dword ptr [PLY], eax
  mov dword ptr [PRX], eax
  mov dword ptr [PRY], eax
  mov dword ptr [PLT], eax
  mov dword ptr [PRT], eax
  popad
  xor eax, eax
  ret

# ---------------------------------------------------------------------------------------------------------------
  .p2align 2
ftab:                                # the pad functions (bit 0, 1, 2 ...): the HELLBEND.INI key variable of each
  .long 0x51275c                     # 0x0001 Fire (fireKey)                A, RT
  .long 0x512758                     # 0x0002 Afterburner (weaponKey)       LT
  .long 0x512778                     # 0x0004 Throttle Up                   right stick up
  .long 0x51277c                     # 0x0008 Throttle Down                 right stick down
  .long 0x512770                     # 0x0010 Roll Left                     right stick left
  .long 0x512774                     # 0x0020 Roll Right                    right stick right
  .long 0x5127e4                     # 0x0040 Change Views (keyChangeViews) Y
  .long 0x5127e8                     # 0x0080 Toggle Instruments            X
  .long 0x512784                     # 0x0100 Missile Target                B
  .long 0x5127e0                     # 0x0200 Select Next Weapon            RB
  .long 0x5127dc                     # 0x0400 Select Previous Weapon        LB
  .long 0x512798                     # 0x0800 Map                           R3
  .long 0x5127ac                     # 0x1000 Toggle Crosshair              L3
  .long 0
btab:                                # XInput button (word), its function bit (word)
  .word 0x8000, 0x0040               # Y
  .word 0x4000, 0x0080               # X
  .word 0x2000, 0x0100               # B
  .word 0x0200, 0x0200               # RB
  .word 0x0100, 0x0400               # LB
  .word 0x0080, 0x0800               # R3
  .word 0x0040, 0x1000               # L3
  .word 0, 0
s_xgs:       .asciz "XInputGetState"
s_retrodeck: .asciz "Retrodeck"
s_invy:      .asciz "PadInvertY"
s_quick:     .asciz "data\\QUICK.HEL"
s_d3d:       .asciz "Direct3D"
  .p2align 4
s_xinput:    .asciz "xinput1_4.dll"
  .p2align 4
             .asciz "xinput1_3.dll"
  .p2align 4
             .asciz "xinput9_1_0.dll"
