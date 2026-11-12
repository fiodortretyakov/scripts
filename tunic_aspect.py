"""Repoint individual Tunic aspect-ratio code sites at a private constant.

The 16:9 float 1.7777779f is deduped into ONE .rdata literal shared by three code
sites, so editing it in place moves the UI scale as well as the camera. Instead we
park a new float in .rdata tail padding and rewrite only the chosen sites' disp32.
"""
import struct, sys, shutil, hashlib

GAME = r"C:\Program Files (x86)\Steam\steamapps\common\TUNIC"
DLL = GAME + r"\GameAssembly.dll"
PRISTINE = GAME + r"\GameAssembly.dll.bak16x9"

LITERAL_OFF = 0xFDDCD8          # the shared 1.7777779f literal
ORIG = bytes.fromhex("398EE33F")
NEW_CONST_OFF = 0x12912B0       # 16-byte-aligned slot in .rdata tail padding
NEW_CONST_RVA = 0x1292AB0

SITES = {                       # name -> file offset of the disp32 field
    1: 0x57876F,                # RuntimeQualityManager.setUpTexture  (world render texture)
    2: 0x7CA704,                # CameraResizer.Update                (camera rect)
    3: 0x7CFDFA,                # ClearingCameraResizer.OnPreRender
}

# CanvasScaler.HandleScaleWithScreenSize @ rva 0x88FFC0 (file rva-0x1200).
# At +0x12E the mode switch reads m_ScreenMatchMode and branches. Replacing
# `test ecx,ecx / je MatchWidthOrHeight` with `jmp Expand` forces every canvas onto
# scaleFactor = Min(w/refW, h/refH), i.e. height-driven on any aspect wider than the
# reference. Without this, widening the camera rect (site 2) doubles the whole UI.
CANVAS_OFF = 0x88EDC0 + 0x12E
CANVAS_ORIG = bytes.fromhex("85C97446")
CANVAS_NEW = bytes.fromhex("EB2C9090")   # jmp +0x2C -> +0x15C (the Mathf.Min branch)


def sections(d):
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    optsz = struct.unpack_from("<H", d, pe + 20)[0]
    out = []
    for i in range(nsec):
        o = pe + 24 + optsz + i * 40
        vsz, va, rsz, raw = struct.unpack_from("<IIII", d, o + 8)
        out.append((raw, rsz, va))
    return out


def off2rva(secs, off):
    for raw, rsz, va in secs:
        if raw <= off < raw + rsz:
            return va + (off - raw)
    raise ValueError(off)


def main(aspect, which):
    shutil.copyfile(PRISTINE, DLL)          # always start from untouched vanilla
    d = bytearray(open(DLL, "rb").read())
    secs = sections(d)

    assert bytes(d[LITERAL_OFF:LITERAL_OFF + 4]) == ORIG, "vanilla literal missing"
    assert set(d[NEW_CONST_OFF:NEW_CONST_OFF + 4]) == {0}, "constant slot not free"

    d[NEW_CONST_OFF:NEW_CONST_OFF + 4] = struct.pack("<f", aspect)

    for s in which:
        off = SITES[s]
        disp = NEW_CONST_RVA - off2rva(secs, off + 4)
        d[off:off + 4] = struct.pack("<i", disp)
        print(f"  site {s} @0x{off:x} -> disp 0x{disp & 0xFFFFFFFF:08x}")

    if which:
        assert bytes(d[CANVAS_OFF:CANVAS_OFF + 4]) == CANVAS_ORIG, "canvas switch moved"
        d[CANVAS_OFF:CANVAS_OFF + 4] = CANVAS_NEW
        print(f"  CanvasScaler @0x{CANVAS_OFF:x} -> forced Expand (height-driven UI)")

    open(DLL, "wb").write(d)
    v = open(DLL, "rb").read()
    print(f"shared literal still {struct.unpack('<f', v[LITERAL_OFF:LITERAL_OFF+4])[0]}")
    print(f"private constant  = {struct.unpack('<f', v[NEW_CONST_OFF:NEW_CONST_OFF+4])[0]}")
    print("sites repointed:", which, "sha256:", hashlib.sha256(v).hexdigest()[:16])


if __name__ == "__main__":
    main(float(sys.argv[1]), [int(x) for x in sys.argv[2].split(",")] if sys.argv[2] else [])
