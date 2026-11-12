"""Risen (2023 64-bit) 32:9 fix for focus-name labels and the focus marker image, plus their size.

gCGUIEntityRenderer draws in a 1920x1080 layout and scales it by (width/1920, height/1080),
which is 2x too wide on 32:9. These edits make both axes use height/REF (uniform scale,
positions unchanged). REF also sets the SIZE: the drawn scale is screenHeight/REF, so a smaller
REF makes the labels bigger. 1080 = original size, 720 = 1.5x bigger, 540 = 2x bigger.

  python risen_focus_text_fix.py             apply, keep the current size (720 on a fresh patch)
  python risen_focus_text_fix.py --ref 540   apply and set the size reference
  python risen_focus_text_fix.py --restore   undo everything

Steam "verify integrity" or a game update restores Game.dll: just run this again.
"""
import hashlib, os, shutil, struct, sys

GAME = r'C:\Program Files (x86)\Steam\steamapps\common\Risen\bin\Game.dll'
REF_RVA = 0xf61b04          # the float the six instructions below divide by (vanilla 1080.0)
DEFAULT_REF = 720.0
# (rva, original bytes, patched bytes)
PATCHES = [
    (0x879b34, '660f6e45b8', '660f6e45bc'),                 # CalcTextRect: load viewport height instead of width
    (0x879b51, 'f30f5e05af7f6e00', 'f30f5e05ab7f6e00'),     # CalcTextRect: divide by REF instead of 1920
    (0x87a2f8, '660f6e442430', '660f6e442434'),             # OnBeginFrame: x scale from height ...
    (0x87a304, 'f30f5e05fc776e00', 'f30f5e05f8776e00'),     # ... / REF
    (0x83a5f6, '660f6e5c2468', '660f6e5c246c'),             # focus marker quad: width from height ...
    (0x83a613, 'f30f5e1ded747200', 'f30f5e1de9747200'),     # ... / REF
]


def rva_to_off(b, rva):
    e = struct.unpack_from('<I', b, 0x3c)[0]
    n = struct.unpack_from('<H', b, e + 6)[0]
    osz = struct.unpack_from('<H', b, e + 20)[0]
    for i in range(n):
        o = e + 24 + osz + 40 * i
        vs, va, rs, ro = struct.unpack_from('<IIII', b, o + 8)
        if va <= rva < va + max(vs, rs):
            return ro + rva - va
    raise ValueError(hex(rva))


def main():
    restore = '--restore' in sys.argv
    ref = None
    if '--ref' in sys.argv:
        ref = float(sys.argv[sys.argv.index('--ref') + 1])
        if not 200.0 <= ref <= 2160.0:
            sys.exit('--ref must be between 200 and 2160 (1080 = original size, smaller = bigger text)')

    b = bytearray(open(GAME, 'rb').read())
    bak = GAME + '.bak-vanilla'
    changed = False

    for rva, orig, new in PATCHES:
        o = rva_to_off(b, rva)
        cur = b[o:o + len(orig) // 2].hex()
        want, have = (orig, new) if restore else (new, orig)
        if cur == have:
            b[o:o + len(orig) // 2] = bytes.fromhex(want)
            changed = True
        elif cur != want:
            sys.exit(f'unexpected bytes at {rva:#x}: {cur} - game version differs, NOT patching')

    ro = rva_to_off(b, REF_RVA)
    old_ref = struct.unpack_from('<f', b, ro)[0]
    new_ref = 1080.0 if restore else (ref if ref is not None else (DEFAULT_REF if old_ref == 1080.0 else old_ref))
    if abs(old_ref - new_ref) > 1e-6:
        struct.pack_into('<f', b, ro, new_ref)
        changed = True

    if not changed:
        print('nothing to do (' + ('already restored' if restore else f'already patched, size reference {old_ref:g}') + ')')
        return
    if not restore and not os.path.exists(bak):
        shutil.copy2(GAME, bak)
    open(GAME, 'wb').write(b)
    scale = 1440.0 / new_ref
    print(('restored' if restore else 'patched'), GAME)
    print(f'  size reference {old_ref:g} -> {new_ref:g}   (labels drawn at {scale:.2f}x, 1080 = original)')
    print('  sha256', hashlib.sha256(b).hexdigest()[:16])


if __name__ == '__main__':
    main()
