#!/usr/bin/env python3
"""Patch Hellbender (HELLBEND.EXE on the US retail disc: v1.01, 1,685,504 bytes, MD5 69ffdf565acef74fc82170a7b1fab907,
linked 4 Sep 1996, MSVC 4 / MFC 4 MDI application) into a copy.

  patch_exe.py <HELLBEND.EXE> <out.exe>   write the patched exe (refuses, writes nothing, on any unexpected byte)
  patch_exe.py --check-caves              re-assemble caves.s with clang and compare with CAVE below

New code (caves.s, assembled bytes in CAVE) goes into a section the patch adds: ".rdeck", VA 0x8f2000, 0x2000 bytes
at file offset 0x19b800 (the end of the file: after .reloc the linker left 60 KB of debug data, kept as it is),
readable / writable / executable; its variables from 0x8f3000. The section table had room for a seventh entry (it
ended at 0x268, the first section starts at 0x400); SizeOfImage 0x4f2000 -> 0x4f4000. The exe has no checksum and
loads at its 0x400000 base; the header now also says "relocations stripped", so no loader ever moves it.

The game (docs/TECHNICAL.md): an MFC MDI program. On Windows NT, which Wine is (GetVersion 0x4399ae: NT gets
"0x350"), it runs in a 640x480 window with a menu bar and draws its software-rendered 8-bit picture with GDI
(StretchBlt to its view's client size, 0x438620 / 0x438b.. / 0x447xxx); full screen was DirectDraw (640x480 only
on NT; Direct3D only full screen). Movement is timed by timeGetTime (0x46f160), every loop draws flat out through
0x46f300. Its message pump (0x43a2a0) never waits. Keys: a scan-code table filled in PreTranslateMessage (0x43ba10).
Joystick: winmm, off on NT. Movies: Smacker (SMACKW32.DLL) into the view, zoomed to its client size. CD audio: MCI
cdaudio (mciSendCommand). Settings: SYSTEM\\HELLBEND.INI.

Patches (va: what was there -> what is there now):
  ram         0x439fd3, 0x439e71: "call [GlobalMemoryStatus]" -> call memstat: every figure clamped to 2 GB - 1
              (Proton's forced large-address-aware flag: dwTotalPhys negative at 0x41ef71, the free-memory sum at
              0x439ffe wrapping to "may not function properly without 16MB").
  renderer    0x43a21c: "mov esi, [useDirect3D]; call 0x402160" (DirectDraw / Direct3D set-up) -> call renderer:
              HELLBEND.INI [Retrodeck] Direct3D=1: Direct3D, full screen, 640x480 forced on, then the set-up
              (dgVoodoo2 is the DirectDraw / Direct3D); 0: no DirectDraw at all, the GDI window path patched below;
              missing (Windows: no launch script writes it): the game's own "Use Hardware Accelerator" decides.
  window      0x49ecc0 PreCreateWindow -> jmp precreate (WS_POPUP covering the screen); 0x49ec30 OnGetMinMaxInfo
              -> jmp minmax (the screen, not 640x480); 0x49ecf0 CMainFrame::WindowProc -> jmp framewp (client area =
              the centred 4:3 box, black bars, no menu bar drawn, no pointer, the frame kept at the screen's size).
  pump        0x43a2a0: the pump's first instructions -> jmp pumphook: the MDI client's and the view's sunken edges off
              (once), the pad, 2 ms asleep when idle in a dialog box / movie / the background.
  idle        0x43b0b0: the app's OnIdle (only between games) -> jmp idlehook: Quick Configuration again after a game
              (the original left the bare window for its menu bar). 0x46f3af: the background loop's "mov eax, [ecx];
              call [eax + 0x60]" -> call idlepump (Sleep(5) first).
  framecap    0x46f300: "mov ecx, [0x5042d0]" (show a frame) -> jmp framecap: at most 60 frames a second, sleeping.
  keywait     0x46f21c: the "wait for a key" loop's "call 0x46f360" -> call keywait: Sleep(5), pad A = Y, B = N.
  keys        0x43ba10: PreTranslateMessage's first instructions -> jmp keyfilter: Enter / Esc / Space end a movie;
              Enter in a game = P (pause); F11 / F12 = Save Game / Resume Game.
  mainmenu    0x448a10: Quick Configuration's Main Menu button (closed the box, leaving the bare window and its menu
              bar, which is gone) -> jmp mainmenu: posts Options > Settings first (the box comes back afterwards).
  quicksave   0x44dac0: Save Game's "no file name yet: Save As box" -> call quicksave; jmp 0x44dacc: data\\QUICK.HEL.
  joyinit     0x45bde0: the joystick set-up (off on NT) -> jmp joyinit: mode 2 (joystick), fixed calibration.
  joyread     0x45bf90, 0x45c0d0: the joystick reads (nothing on NT) -> jmp joyread (padupdate: the pad by XInput).
  joydevs     0x448d5b, 0x4900b5: "call [joyGetNumDevs]" -> "mov eax, 16" (the joystick choice never greyed out).
"""
import hashlib, os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE, MD5 = 1685504, "69ffdf565acef74fc82170a7b1fab907"
DELTA = 0x400c00                       # .text (VA 0x401000, file offset 0x400): file offset = VA - 0x400c00
def T(va):
    if 0x401000 <= va < 0x4eb000: return va - DELTA
    raise AssertionError(hex(va))

def rel32(src, dst, op):               # e8 / e9 at src (5 bytes) -> dst
    return bytes([op]) + (dst - (src + 5)).to_bytes(4, "little", signed=True)
NOP = b"\x90"

SECT_VA, SECT_RVA, SECT_OFF, SECT_SIZE = 0x8f2000, 0x4f2000, 0x19b800, 0x2000
CAVE_VA, VARS = SECT_VA, 0x1000        # code from 0x8f2000, variables from 0x8f3000
CAVE = bytes.fromhex(
    "ff742404ff15389d87008b442404b906000000817808ffffff7f7607c74008ffffff7f83c0044975eac20400568b742408c7462000000082"
    "c7462c00000000516a00ff153ca087008946146a01ff153ca0870089461059c7461800000000c7461c0000000056e8b1cfbeff816620ffff"
    "0000814e20000000825ec20400568b7424086a00ff153ca087008946088946206a01ff153ca0870089460c894624c7461000000000c74614"
    "000000005ec204008b4424043d830000000f84af0000003d850000000f84e30000003d86000000741c3d84000000741583f820741883f846"
    "742353568b74240ce909ccbaffb801000000c20c006a00ff15e89f8700b801000000c20c00568b7424108b461883e00383f8037433817e08"
    "0083ffff7e2a516a00ff153ca087008946106a01ff153ca0870089461459c7460800000000c7460c00000000836618fc5eeb975389c38d04"
    "8d0000000031d251b903000000f7f15939d8760889d88d0c5bc1e9025bc35356578b7424188b5e082b1e8b7e0c2b7e0489d889f9e8c2ffff"
    "ff29c3d1fb29cfd1ff031e037e04891e897e0401c301cf895e08897e0c5f5e5b31c0c20c00535657558b691c83ec1089e05055ff1504a087"
    "008b5c24082b1c248b7c240c2b7c240483c41055ff15fc9d870089c685f60f849600000089d889f9e85effffffa344308f00890d48308f00"
    "89da29c2d1fa89154c308f0089fa29cad1fa891550308f006a4257ff354c308f006a006a0056ff15bc998700a14c308f00030544308f0089"
    "da29c26a4257526a005056ff15bc9987006a42ff3550308f00536a006a0056ff15bc998700a150308f00030548308f0089fa29c26a425253"
    "506a0056ff15bc9987005655ff1548a087005d5f5e5b31c0c20c00833d40308f0000757b8b1d6497570085db74716a0553ff15b09f870085"
    "c0746489c66a0556ff15b09f870085c074556a0550ff15b09f870085c0744889c7c70540308f00010000006a006aec56ff15fc9f87006a00"
    "6aec57ff15fc9f87006a376a006a006a006a006a0056ff159c9f87006a376a006a006a006a006a0057ff159c9f8700c360e875ffffffe874"
    "0400006a006a006a006a0068a0308f00ff15ec9f870085c07528833d642d5100007517833dac26510001750eff15c49f87003b0564975700"
    "74086a02ff150c9d87006183ec04a164b95300e9487fb4ff833d34265100007542833dac265100007539833d642d510000753083b9280100"
    "00007527833d5c308f0000751e51c7055c308f00010000008b01ff90b0000000c7055c308f0000000000598b44240483ec04e9008db4ff51"
    "6a05ff150c9d8700598b01ff6060833d60d7500000754d60ff158ca087008d0440833d30308f00007511c70530308f0001000000a334308f"
    "00eb2189c12b0d34308f00790a6a01ff150c9d8700ebc981f9960000007c05a334308f00830534308f0032618b0dd0425000e9dfceb7ffc7"
    "0554308f0001000000e82acfb7ffc70554308f0000000000606a05ff150c9d8700b859000000f70528308f00001000007511b84e000000f7"
    "0528308f00002000007413c70528308f000000000050e825ceb7ff83c40461c3608b7424248b56048b5e0881fa00010000742781fa010100"
    "000f85be00000083fb0d0f85b5000000e8bb00000085c00f84a8000000e99a000000833d642d510000741f83fb0d740a83fb1b740583fb20"
    "7510ff3530a45700e883d1baff83c404eb7283fb0d7527833d54308f0000740c6a59e8a9cdb7ff83c404eb58e86700000085c07458c605d9"
    "365b0001eb4683fb787510e85900000085c07441bf08800000eb1dbf3f80000083fb7a740abf0580000083fb7b7526e82c00000085c0741d"
    "6a00576811010000ff3564975700ff15d49f870061b801000000c204006183ec145356e9ad94b4ff833dac26510001753b833d642d510000"
    "7532578b3e85ff742a6af057ff1538a08700a900000040740b57ff15b49f870089c7ebe13b3d6497570075075fb801000000c35f31c0c368"
    "b02a50006a02680f2c8f0068eb2b8f00ff15609d870083f80275248b352402500085f67414c70578d7500001000000c70574d75000020000"
    "00e872fbb0ffc385c07519c7052402500000000000c70578d750000000000031f631c0c3c7052402500001000000c70578d7500001000000"
    "c70574d7500002000000be01000000e82cfbb0ffc3516a0068088000006811010000ff3564975700ff15d49f870059568b0189cee9bc63b5"
    "ff8d435068002c8f0050ff157c9d87008d5350c360c7057825510002000000c70574365b0000000000c70550d35900ffff0000c70500385b"
    "0000000000c705fcd15900ffff0000c705f0cf590000000000c7057c365b0000000000c7052cd1590000000000c70528d1590000000000c7"
    "05a0365b00ff7f0000c7058c385b00ff7f0000c70520385b0000000000c7057c255100ff3f0000c70524d1590000000000c705c429510008"
    "000000c7058025510000000000c705e8395b0000000000c7054827510000000000c70560365b00ff7f0000c7056c365b00ff7f0000c70540"
    "d1590000000000c70504d1590000000000c7053c308f000100000068b02a50006a0068f52b8f0068eb2b8f00ff15609d8700a338308f0061"
    "c3833d3c308f00007505e8edfeffff60e80200000061c360e80703000085c00f84fc0100008b3508308f00f7c6008000007445833dac2651"
    "00017546833d8cf5500000743d81e6ff7fffff833d60308f0000752ec70560308f00010000006a0068088000006811010000ff3564975700"
    "ff15d49f8700eb0ac70560308f0000000000a10c308f00e85f0200008d81ff7f0000a360365b00a110308f00e84a020000833d38308f0000"
    "7502f7d98d81ff7f0000a36c365b0089f0c1e80c83e001a3103a5b0089f083e001a32827510089f0d1e883e001a32c27510089f0c1e80283"
    "e001a33027510089f0c1e80383e001a33427510031fff7c6001000007509833d20308f0028720383cf01833d1c308f0028720383cf02a118"
    "308f003d803e00007c0383cf043d80c1ffff7f0383cf08a114308f003d80c1ffff7f0383cf103d803e00007c0383cf20bbbc2b8f000fb703"
    "85c0740f85c674060fb7430209c783c304ebea8b152c308f00893d2c308f0089d0f7d021f8f7d721d789c2bb842b8f00b9010000008b0385"
    "c074248b0025ff00000085ca7407c680c0365b000185cf7407c680c0365b000083c304d1e1ebd68b3d24308f00893524308f0089f8f7d021"
    "f0a328308f0089c3833d642d5100007420f7c300f0000074186801001c006a0d6800010000ff3564975700ff15d49f8700f7c31000000074"
    "0fbf0d000000be01001c00e8ae000000f7c320000000740fbf1b000000be01000100e89700000061c3c70560365b00ff7f0000c7056c365b"
    "00ff7f0000c705103a5b0000000000c7052827510000000000c7052c27510000000000c7053027510000000000c70534275100000000008b"
    "3d2c308f00bb842b8f00b9010000008b0385c0741985cf740e8b0025ff000000c680c0365b000083c304d1e1ebe1c7052c308f0000000000"
    "c70524308f0000000000c70528308f000000000061c3ff15c49f870085c07505a16497570089c55657680001000055ff15d49f870089f00d"
    "000000c05057680101000055ff15d49f8700c389c1c1f91f31c829c82d581b00007f0331c9c35169c0ff7f000031d253bba8640000f7f35b"
    "3dff7f00007605b8ff7f00005931c829c889c1c360833d04308f0000753cc70504308f0001000000be202c8f00bb0300000056ff15289d87"
    "0085c0741768dc2b8f0050ff152c9d870085c07407a300308f00eb0683c6104b75d8833d00308f0000747531db6880308f0053ff1500308f"
    "0085c074084383fb0472eaeb5b0fb70584308f00a308308f000fb60586308f00a31c308f000fb60587308f00a320308f000fbf0588308f00"
    "a30c308f000fbf058a308f00a310308f000fbf058c308f00a314308f000fbf058e308f00a318308f0061b801000000c331c0a308308f00a3"
    "0c308f00a310308f00a314308f00a318308f00a31c308f00a320308f006131c0c30f1f005c27510058275100782751007c27510070275100"
    "74275100e4275100e827510084275100e0275100dc27510098275100ac275100000000000080400000408000002000010002000200010004"
    "80000008400000100000000058496e707574476574537461746500526574726f6465636b00506164496e766572745900646174615c515549"
    "434b2e48454c004469726563743344000f1f84000000000078696e707574315f342e646c6c00669078696e707574315f332e646c6c006690"
    "78696e707574395f315f302e646c6c00")
SYM = {"memstat": 0x0, "precreate": 0x2c, "minmax": 0x7d, "framewp": 0xb0, "pumphook": 0x308, "idlehook": 0x360, "idlepump": 0x3b7, "framecap": 0x3c6, "keywait": 0x427, "keyfilter": 0x480, "quicksave": 0x659, "renderer": 0x5af, "mainmenu": 0x635, "joyinit": 0x66c, "joyread": 0x771}   # labels of caves.s
def C(name): return CAVE_VA + SYM[name]

def build():
    """(va, old bytes, new bytes) for every patch site."""
    e = []
    # ram: "call [GlobalMemoryStatus]" -> call memstat
    for va in (0x439fd3, 0x439e71):
        e.append((va, bytes.fromhex("ff15389d8700"), rel32(va, C("memstat"), 0xe8) + NOP))
    # renderer: "mov esi, [0x500224]; call 0x402160" -> call renderer
    e.append((0x43a21c, bytes.fromhex("8b3524025000e8397ffcff"), rel32(0x43a21c, C("renderer"), 0xe8) + NOP * 6))
    # window: PreCreateWindow "mov eax, [esp + 4]; push eax", OnGetMinMaxInfo "sub esp, 0x20; lea eax, [esp + ..]",
    # WindowProc "push ebx; push esi; mov esi, [esp + 0xc]"
    e.append((0x49ecc0, bytes.fromhex("8b44240450"), rel32(0x49ecc0, C("precreate"), 0xe9)))
    e.append((0x49ec30, bytes.fromhex("83ec208d44"), rel32(0x49ec30, C("minmax"), 0xe9)))
    e.append((0x49ecf0, bytes.fromhex("53568b74240c"), rel32(0x49ecf0, C("framewp"), 0xe9) + NOP))
    # pump: "sub esp, 4; mov eax, [0x53b964]" -> jmp pumphook
    e.append((0x43a2a0, bytes.fromhex("83ec04a164b95300"), rel32(0x43a2a0, C("pumphook"), 0xe9) + NOP * 3))
    # idle: OnIdle's "mov eax, [esp + 4]; sub esp, 4" -> jmp idlehook
    e.append((0x43b0b0, bytes.fromhex("8b44240483ec04"), rel32(0x43b0b0, C("idlehook"), 0xe9) + NOP * 2))
    # idle: "mov eax, [ecx]; call [eax + 0x60]" -> call idlepump
    e.append((0x46f3af, bytes.fromhex("8b01ff5060"), rel32(0x46f3af, C("idlepump"), 0xe8)))
    # framecap: "mov ecx, [0x5042d0]" -> jmp framecap
    e.append((0x46f300, bytes.fromhex("8b0dd0425000"), rel32(0x46f300, C("framecap"), 0xe9) + NOP))
    # keywait: "call 0x46f360" -> call keywait
    e.append((0x46f21c, rel32(0x46f21c, 0x46f360, 0xe8), rel32(0x46f21c, C("keywait"), 0xe8)))
    # keys: "sub esp, 0x14; push ebx; push esi" -> jmp keyfilter
    e.append((0x43ba10, bytes.fromhex("83ec145356"), rel32(0x43ba10, C("keyfilter"), 0xe9)))
    # quicksave: "mov ecx, ebx; call 0x44db00" -> "call quicksave; jmp 0x44dacc"
    e.append((0x44dac0, bytes.fromhex("8bcbe839000000"), rel32(0x44dac0, C("quicksave"), 0xe8) + bytes.fromhex("eb05")))
    # mainmenu: Quick Configuration's Main Menu button "push esi; mov eax, [ecx]; mov esi, ecx" -> jmp mainmenu
    e.append((0x448a10, bytes.fromhex("568b018bf1"), rel32(0x448a10, C("mainmenu"), 0xe9)))
    # joyinit: "sub esp, 0x194" -> jmp joyinit; joyread: the reads' first bytes -> jmp joyread
    e.append((0x45bde0, bytes.fromhex("81ec94010000"), rel32(0x45bde0, C("joyinit"), 0xe9) + NOP))
    e.append((0x45bf90, bytes.fromhex("83ec44a1bc"), rel32(0x45bf90, C("joyread"), 0xe9)))
    e.append((0x45c0d0, bytes.fromhex("a1bc9a5700"), rel32(0x45c0d0, C("joyread"), 0xe9)))
    # joydevs: "call [joyGetNumDevs]" -> "mov eax, 16"
    for va in (0x448d5b, 0x4900b5):
        e.append((va, bytes.fromhex("ff1590a08700"), bytes.fromhex("b810000000") + NOP))
    return e

def add_section(data):
    lfanew = struct.unpack_from("<I", data, 0x3c)[0]
    nsec = struct.unpack_from("<H", data, lfanew + 6)[0]
    optsize = struct.unpack_from("<H", data, lfanew + 20)[0]
    sh = lfanew + 24 + optsize + 40 * nsec
    if nsec != 6 or sh != 0x268 or any(data[sh:sh + 40]) or len(data) != SECT_OFF:
        sys.exit("unexpected PE header; nothing written")
    struct.pack_into("<8sIIIIIIHHI", data, sh, b".rdeck", SECT_SIZE, SECT_RVA, SECT_SIZE, SECT_OFF, 0, 0, 0, 0,
                     0xE0000060)       # code | initialised data | execute | read | write
    struct.pack_into("<H", data, lfanew + 6, nsec + 1)
    chars = struct.unpack_from("<H", data, lfanew + 22)[0]
    struct.pack_into("<H", data, lfanew + 22, chars | 1)     # IMAGE_FILE_RELOCS_STRIPPED
    if struct.unpack_from("<I", data, lfanew + 24 + 56)[0] != SECT_RVA: sys.exit("unexpected SizeOfImage")
    struct.pack_into("<I", data, lfanew + 24 + 56, SECT_RVA + SECT_SIZE)
    data += CAVE + bytes(SECT_SIZE - len(CAVE))

def elf_text(path):                    # .text bytes and label offsets of an i386 ELF object (no relocations)
    d = open(path, "rb").read()
    shoff = struct.unpack_from("<I", d, 0x20)[0]; shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x2e)
    secs = [struct.unpack_from("<10I", d, shoff + i * shentsize) for i in range(shnum)]
    names = [d[secs[shstrndx][4] + x[0]:].split(b"\0")[0].decode() for x in secs]
    if any(n.startswith(".rel") and x[5] for n, x in zip(names, secs)): sys.exit("caves.o has relocations")
    ti = names.index(".text"); text = d[secs[ti][4]:secs[ti][4] + secs[ti][5]]; syms = {}
    for x in secs:
        if x[1] != 2: continue                                   # SHT_SYMTAB
        strs = secs[x[6]]
        for i in range(x[5] // 16):
            nm, val, size, info, oth, shn = struct.unpack_from("<IIIBBH", d, x[4] + 16 * i)
            if shn == ti: syms[d[strs[4] + nm:].split(b"\0")[0].decode()] = val
    return text, syms

ENTRIES = ("memstat", "precreate", "minmax", "framewp", "pumphook", "idlehook", "idlepump", "framecap", "keywait", "keyfilter",
           "quicksave", "renderer", "mainmenu", "joyinit", "joyread")
def assemble():
    with tempfile.TemporaryDirectory() as t:
        o = os.path.join(t, "caves.o")
        subprocess.run(["clang", "-target", "i386-pc-linux-gnu", "-c", os.path.join(HERE, "caves.s"), "-o", o], check=True)
        return elf_text(o)

def check_caves():
    text, syms = assemble()
    ok = text == CAVE and all(syms.get(k) == SYM.get(k) for k in ENTRIES)
    print("caves.s matches CAVE" if ok else "caves.s differs from CAVE / SYM: update patch_exe.py")
    if not ok:
        print("CAVE =", text.hex()); print("SYM =", {k: hex(syms[k]) for k in ENTRIES})
    return ok

def patch(data, label="HELLBEND.EXE"):
    """Returns the patched exe; exits on any unexpected byte."""
    data = bytearray(data)
    if len(data) != SIZE or hashlib.md5(data).hexdigest() != MD5:
        sys.exit(f"{label}: not Hellbender's HELLBEND.EXE v1.01 (size {SIZE}, MD5 {MD5}); nothing written")
    assert 0 < len(CAVE) < VARS, "CAVE empty or running into the variables at 0x8f3000"
    edits = build()
    for va, old, new in edits:
        off = T(va)
        if bytes(data[off:off + len(old)]) != old or len(old) != len(new):
            sys.exit(f"unexpected bytes at VA {va:#x}; nothing written")
    for va, old, new in edits:
        data[T(va):T(va) + len(new)] = new
    add_section(data)
    print(f"  rdeck ram renderer window pump idle framecap keywait keys quicksave mainmenu joyinit joyread joydevs "
          f"({len(edits)} edits)")
    return bytes(data)

def main(src, dst):
    data = patch(open(src, "rb").read(), src)
    tmp = dst + ".tmp"
    open(tmp, "wb").write(data)
    os.replace(tmp, dst)
    print(f"{dst}: MD5 {hashlib.md5(data).hexdigest()}")

if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--check-caves": sys.exit(0 if check_caves() else 1)
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
