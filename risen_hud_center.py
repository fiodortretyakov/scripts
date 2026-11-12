#!/usr/bin/env python3
"""Risen (Steam 40300, 2023 64-bit build) - centre the 16:9 HUD on a wider screen.

Patches eCGuiModule2::ReSize(long w, long h) in bin\\Engine.dll so that the GUI draw scale is uniform
(X scale = Y scale = h / VirtalHeight) and the GUI X offset = (w - VirtalWidth * scale) / 2.
The engine already applies scale + offset to drawing, mouse mapping and focus position, so nothing
else needs to change. The 3D world is untouched (it follows the window aspect).

usage:  python risen_hud_center.py            apply (idempotent: restores vanilla from the backup first)
        python risen_hud_center.py --restore  put the vanilla DLL back
"""
import hashlib, os, shutil, struct, sys

GAME_BIN = r"C:\Program Files (x86)\Steam\steamapps\common\Risen\bin"
DLL = os.path.join(GAME_BIN, "Engine.dll")
BAK = os.path.join(GAME_BIN, "Engine.dll.bak-vanilla")
VANILLA_SHA256 = "PLACEHOLDER"  # filled on first run from the shipped file (build 10475629)

TEXT_VA, TEXT_RAW = 0x1000, 0x400          # .text section of this build
def r2o(rva): return rva - TEXT_VA + TEXT_RAW

RESIZE_PATCH_RVA = 0x51A6F5                # inside ?ReSize@eCGuiModule2@@QEAA_NJJ@Z, start of the DrawScale branch maths
RESIZE_RETURN_RVA = 0x51A735               # movss [rbx+0x20], xmm2 ... (stores sx, sy, sz=1, returns)
CAVE_RVA = 0x802C98                        # zero padding at the end of .text raw data (360 bytes)
ORIG_RESIZE = bytes.fromhex(
    "66 0f 6e 43 38 0f 5b c0 66 0f 6e cf 0f 5b c9 66 0f 6e d6 f3 0f 5e c8 "
    "66 0f 6e 43 34 0f 5b c0 0f 5b d2 f3 0f 5e d0 eb 18")           # 40 bytes, ends with jmp 0x51A735
assert len(ORIG_RESIZE) == 40

def rel32(src_end, dst): return struct.pack("<i", dst - src_end)

def cave_code():
    c = bytearray()
    c += bytes.fromhex("66 0f 6e 43 38")   # movd     xmm0, [rbx+0x38]   VirtalHeight
    c += bytes.fromhex("0f 5b c0")         # cvtdq2ps xmm0, xmm0
    c += bytes.fromhex("66 0f 6e cf")      # movd     xmm1, edi          h
    c += bytes.fromhex("0f 5b c9")         # cvtdq2ps xmm1, xmm1
    c += bytes.fromhex("f3 0f 5e c8")      # divss    xmm1, xmm0         sy = h / VH
    c += bytes.fromhex("0f 28 d1")         # movaps   xmm2, xmm1         sx = sy
    c += bytes.fromhex("66 0f 6e 43 34")   # movd     xmm0, [rbx+0x34]   VirtalWidth
    c += bytes.fromhex("0f 5b c0")         # cvtdq2ps xmm0, xmm0
    c += bytes.fromhex("f3 0f 59 c1")      # mulss    xmm0, xmm1         VW * sy  (scaled canvas width)
    c += bytes.fromhex("f3 0f 2c c0")      # cvttss2si eax, xmm0
    c += bytes.fromhex("8b ce")            # mov      ecx, esi           w
    c += bytes.fromhex("2b c8")            # sub      ecx, eax           w - VW*sy
    c += bytes.fromhex("d1 f9")            # sar      ecx, 1             / 2
    c += bytes.fromhex("89 4b 2c")         # mov      [rbx+0x2c], ecx    offset x
    c += bytes.fromhex("33 c0")            # xor      eax, eax
    c += bytes.fromhex("89 43 30")         # mov      [rbx+0x30], eax    offset y = 0
    c += b"\xe9" + rel32(CAVE_RVA + len(c) + 5, RESIZE_RETURN_RVA)   # jmp back
    return bytes(c)

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""): h.update(chunk)
    return h.hexdigest().upper()

def main():
    restore = "--restore" in sys.argv
    if not os.path.exists(BAK):
        d = open(DLL, "rb").read()
        assert d[r2o(RESIZE_PATCH_RVA):r2o(RESIZE_PATCH_RVA) + 40] == ORIG_RESIZE, "Engine.dll is not the expected vanilla build (ReSize bytes differ)"
        assert set(d[r2o(CAVE_RVA):r2o(CAVE_RVA) + 0x60]) <= {0xCC, 0x00}, "code cave is not empty"
        shutil.copy2(DLL, BAK); print("vanilla backup written:", BAK, sha(BAK))
    shutil.copy2(BAK, DLL)
    if restore:
        print("restored vanilla Engine.dll", sha(DLL)); return
    d = bytearray(open(DLL, "rb").read())
    assert d[r2o(RESIZE_PATCH_RVA):r2o(RESIZE_PATCH_RVA) + 40] == ORIG_RESIZE
    assert set(d[r2o(CAVE_RVA):r2o(CAVE_RVA) + 0x60]) <= {0xCC, 0x00}
    hook = b"\xe9" + rel32(RESIZE_PATCH_RVA + 5, CAVE_RVA) + b"\x90" * 35
    d[r2o(RESIZE_PATCH_RVA):r2o(RESIZE_PATCH_RVA) + 40] = hook
    code = cave_code(); d[r2o(CAVE_RVA):r2o(CAVE_RVA) + len(code)] = code
    # the cave sits past .text's VirtualSize (inside its raw padding): extend VirtualSize so every loader maps it
    pe = struct.unpack_from("<I", d, 0x3c)[0]; nsec = struct.unpack_from("<H", d, pe + 6)[0]; szopt = struct.unpack_from("<H", d, pe + 20)[0]
    for i in range(nsec):
        sh = pe + 24 + szopt + 40 * i
        if d[sh:sh + 5] == b".text":
            vs, va, rs = struct.unpack_from("<III", d, sh + 8); need = CAVE_RVA + len(code) - va
            assert va == TEXT_VA and need <= rs
            if vs < need: struct.pack_into("<I", d, sh + 8, need); print(".text VirtualSize 0x%X -> 0x%X" % (vs, need))
    open(DLL, "wb").write(d)
    print("patched: hook @0x%X -> cave @0x%X (%d bytes), return @0x%X" % (RESIZE_PATCH_RVA, CAVE_RVA, len(code), RESIZE_RETURN_RVA))
    print("patched sha256:", sha(DLL))

if __name__ == "__main__":
    main()
