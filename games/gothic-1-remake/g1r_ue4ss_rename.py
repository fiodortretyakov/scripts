"""Gothic 1 Remake 1.1 blocks a module named UE4SS.dll. Load UE4SS as RE4SS.dll instead:
patch 'UE4SS.dll' -> 'RE4SS.dll' (first byte U->R) in the loader proxy and in native mod imports, then rename the DLL.
Each patch checks the exact expected bytes first; 'revert' does the reverse. Usage: g1r_ue4ss_rename.py <Win64 dir> apply|revert"""
import hashlib, os, shutil, sys
win64, mode = sys.argv[1], sys.argv[2]
OLD, NEW = (b"U", b"R") if mode == "apply" else (b"R", b"U")
PATCHES = [  # file, offset, encoding of the standalone "UE4SS.dll" string
    ("dwmapi.dll", 0x9080, "ascii"),
    ("dwmapi.dll", 0x90A8, "utf-16-le"),
    ("ue4ss/Mods/G1R_UncapTeach/dlls/main.dll", 0x25EE6, "ascii"),
]
def sha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()[:12].upper()
data = {}
for rel, off, enc in PATCHES:
    p = os.path.join(win64, rel)
    buf = data.setdefault(rel, bytearray(open(p, "rb").read()))
    want = (OLD.decode() + "E4SS.dll").encode(enc) + b"\0" * (2 if enc == "utf-16-le" else 1)
    got = bytes(buf[off:off + len(want)])
    if got != want:
        sys.exit(f"ABORT {rel} @0x{off:X}: expected {want!r}, found {got!r}; nothing written")
    buf[off] = NEW[0]
for rel, buf in data.items():
    p = os.path.join(win64, rel)
    before = sha(p)
    with open(p, "r+b") as f:
        f.write(buf)
    print(f"{rel}: {before} -> {sha(p)} ({len(buf)} bytes)")
src, dst = ("ue4ss/UE4SS.dll", "ue4ss/RE4SS.dll") if mode == "apply" else ("ue4ss/RE4SS.dll", "ue4ss/UE4SS.dll")
os.rename(os.path.join(win64, src), os.path.join(win64, dst))
print(f"renamed {src} -> {dst} ({sha(os.path.join(win64, dst))})")
