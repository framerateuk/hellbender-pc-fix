#!/usr/bin/env python3
"""Build a ready-to-run Hellbender folder for modern PCs from your own CD.

Usage:
  python3 build.py DISC.cue|DISC.ccd --dgvoodoo DGVOODOO.zip --ogg-winmm OGG-WINMM.zip [--out DIR] [--windows]

  DISC          your Hellbender CD (Microsoft, 1996, v1.01) as .cue + .bin or .ccd + .img, with its audio tracks
  --dgvoodoo    dgVoodoo2 2.79.3 zip (or its unpacked folder)
  --ogg-winmm   ogg-winmm v2025.01.16 release zip (or folder)
  --out         where to create Hellbender/ (default: this folder)
  --windows     a folder for Windows: the game's own "Use Hardware Accelerator" box picks the renderer (on at
                first), no launch script. Without it: the Steam Deck build, renderer picked by the launch script

Needs Python 3.8+ and an Ogg Vorbis encoder on the PATH: oggenc (vorbis-tools) or ffmpeg.
Nothing from the game is in this repository: every game file comes from your disc.
"""
import argparse, hashlib, os, shutil, struct, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import disc, oggwinmm_fix, patch_exe

POD_MD5 = "cc775fd53a7ecaf1c94da1839a1991cb"           # system\GAME.POD, the game data
PATCHED_MD5 = "0047c628f4b15b723d0be39947eabb90"


def md5(data): return hashlib.md5(data).hexdigest()


def encoder():
    if shutil.which("oggenc"): return lambda wav, ogg: ["oggenc", "-Q", "-q", "7", wav, "-o", ogg]
    if shutil.which("ffmpeg"):
        return lambda wav, ogg: ["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "7", ogg]
    sys.exit("needs oggenc (vorbis-tools) or ffmpeg on the PATH to encode the soundtrack")


def rip(tracks, music):
    enc = encoder(); os.makedirs(music, exist_ok=True); n = 0
    with tempfile.TemporaryDirectory() as tmp:
        for t in tracks:
            if t.kind != "AUDIO": continue
            data = disc.audio(t)          # INDEX 01 to the next track's start: lengths match the disc's TOC
            wav = os.path.join(tmp, f"track{t.n:02d}.wav")
            with open(wav, "wb") as o:
                o.write(b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " +
                        struct.pack("<IHHIIHH", 16, 1, 2, 44100, 176400, 4, 16) + b"data" +
                        struct.pack("<I", len(data)) + data)
            subprocess.run(enc(wav, os.path.join(music, f"Track{t.n:02d}.ogg")), check=True); os.remove(wav)
            print(f"  Music/Track{t.n:02d}.ogg  {len(data) / 2352 / 75:6.1f} s"); n += 1
    if n != 8: sys.exit(f"expected 8 audio tracks (the game's music), found {n}: is the image missing them?")


def take(src, member):
    """Bytes of the file whose path ends with `member` (case-insensitive) in a zip or folder."""
    want = member.lower()
    if os.path.isdir(src):
        for d, _, fs in os.walk(src):
            for f in fs:
                p = os.path.join(d, f)
                if os.path.relpath(p, src).replace(os.sep, "/").lower().endswith(want): return open(p, "rb").read()
    else:
        with zipfile.ZipFile(src) as z:
            for name in z.namelist():
                if name.lower().endswith(want): return z.read(name)
    sys.exit(f"{member} not found in {src}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("disc"); ap.add_argument("--dgvoodoo", required=True); ap.add_argument("--ogg-winmm", required=True)
    ap.add_argument("--out", default=HERE); ap.add_argument("--windows", action="store_true")
    a = ap.parse_args()

    tracks = disc.tracks(a.disc)
    data = [t for t in tracks if t.kind != "AUDIO"]
    if not data: sys.exit("no data track in " + a.disc)
    dt = disc.DataTrack(data[0])
    entries = {p.upper(): (p, is_dir, l, s) for p, is_dir, l, s in dt.walk()}
    for key, want in [("HELLBEND.EXE", patch_exe.MD5), ("SYSTEM/GAME.POD", POD_MD5)]:
        if key not in entries: sys.exit(f"no {key} on this CD: it isn't the Hellbender disc the kit was made for")
        got = md5(dt.read_file(*entries[key][2:]))
        if got != want:
            sys.exit(f"this CD's {key} is not the v1.01 one the kit was made for (MD5 {got}); nothing else is supported yet")
    winmm = oggwinmm_fix.patch(take(a.ogg_winmm, "winmm.dll"))    # before anything is written: the release must match

    pkg = os.path.join(os.path.abspath(a.out), "Hellbender"); game = os.path.join(pkg, "game")
    if os.path.exists(pkg): sys.exit(f"{pkg} already exists: move or delete it first")

    print("1/5 game files from the CD")   # what Setup's Typical install copies, plus the movies
    def copy(key, dst): dt.copy_file(*entries[key][2:], os.path.join(game, *dst.split("/")))
    for key, dst in [("SMACKW32.DLL", "SMACKW32.DLL"), ("HELLBEND.HLP", "HELLBEND.HLP"), ("README.DOC", "readme.doc"),
                     ("HELLBEND.EXE", "_spare/HELLBEND.EXE"), ("SYSTEM/HELLBEND.INI", "_spare/HELLBEND.INI")]:
        copy(key, dst)
    movies = 0
    for key, (p, is_dir, l, s) in entries.items():
        if is_dir or key == "SYSTEM/HELLBEND.INI": continue
        if key.startswith("SYSTEM/"):
            copy(key, "system/" + p[len("system/"):]); movies += key.startswith("SYSTEM/STORY/")
        elif key.startswith("SOUND/"):
            copy(key, "Sound/" + p[len("SOUND/"):])
    if movies != 32: sys.exit(f"expected 32 movies in system\\Story, found {movies}")
    os.makedirs(os.path.join(game, "data"))
    ini = "config-windows" if a.windows else "config"
    shutil.copyfile(os.path.join(HERE, ini, "system", "HELLBEND.INI"), os.path.join(game, "system", "HELLBEND.INI"))

    print("2/5 exe patches")
    out = patch_exe.patch(dt.read_file(*entries["HELLBEND.EXE"][2:]))
    if md5(out) != PATCHED_MD5: sys.exit("patching gave an unexpected HELLBEND.EXE")
    open(os.path.join(game, "HELLBEND.EXE"), "wb").write(out)

    print("3/5 soundtrack")
    rip(tracks, os.path.join(game, "Music"))

    print("4/5 wrappers and settings")
    for member, name in [("MS/x86/DDraw.dll", "ddraw.dll"), ("MS/x86/D3DImm.dll", "d3dimm.dll")]:
        open(os.path.join(game, name), "wb").write(take(a.dgvoodoo, member))
    open(os.path.join(game, "winmm.dll"), "wb").write(winmm)
    for f in ("dgVoodoo.conf", "winmm.ini"):
        shutil.copyfile(os.path.join(HERE, "config", f), os.path.join(game, f))

    print("5/5 Steam Deck launch script" if not a.windows else "5/5 done")
    if not a.windows:
        launch = os.path.join(pkg, "hellbender_launch.sh")
        shutil.copyfile(os.path.join(HERE, "steamdeck", "hellbender_launch.sh"), launch); os.chmod(launch, 0o755)
    print(f"\ndone: {pkg}  (see README.md)")


if __name__ == "__main__":
    main()
