import struct, zlib, sys
class Pak:
    def __init__(s, path):
        s.f = open(path, 'rb'); h = s.f.read(48)
        ver, magic = struct.unpack_from('<I4s', h); assert magic == b'G3V0', magic
        s.enc, s.comp = struct.unpack_from('<II', h, 12)
        s.data_off, s.root_off, s.vol_off = struct.unpack_from('<QQQ', h, 24)
        s.f.seek(s.root_off); s.t = s.f.read(s.vol_off - s.root_off if s.vol_off > s.root_off else 50_000_000); s.i = 0
        s.files = {}
        name = s.str_()
        s.i += 24; attr, n = s.u32(), s.u32()
        for _ in range(n): s.entry('')
    def u32(s): v = struct.unpack_from('<I', s.t, s.i)[0]; s.i += 4; return v
    def u64(s): v = struct.unpack_from('<Q', s.t, s.i)[0]; s.i += 8; return v
    def str_(s):
        n = s.u32()
        if n == 0: return ''
        v = s.t[s.i:s.i+n].decode('latin1'); s.i += n + 1; return v
    def entry(s, path):
        attr = s.u32(); name = s.str_(); p = path + '/' + name
        if attr & 0x10:
            s.i += 24; s.u32(); n = s.u32()
            for _ in range(n): s.entry(p)
        else:
            off = s.u64(); s.i += 24; a2, enc, comp, csz, sz = s.u32(), s.u32(), s.u32(), s.u32(), s.u32()
            s.files[p.lower()] = (p, off, comp, csz, sz)
    def read(s, key):
        p, off, comp, csz, sz = s.files[key]; s.f.seek(off); d = s.f.read(csz)
        return zlib.decompress(d) if comp else d
if __name__ == '__main__':
    pk = Pak(sys.argv[1]); print(len(pk.files), 'files', 'comp', pk.comp)
    from collections import Counter
    c = Counter(k.rsplit('.',1)[-1] for k in pk.files); print(dict(c.most_common(12)))
    for k in list(pk.files)[:int(sys.argv[2]) if len(sys.argv) > 2 else 5]: print('  ', pk.files[k][0], pk.files[k][2:])
