import struct, zlib
FT = 0x01DD0000_00000000  # fixed FILETIME (~2026)
def _str(s):
    b = s.encode('latin1'); return struct.pack('<I', len(b)) + (b + b'\0' if b else b'')
def write(path, files, order='desc'):
    """files: {'/Dir/Sub/name.ext': (comp, raw_bytes, size)}  comp 0 = stored, else raw is zlib data."""
    tree = {}
    for p, v in files.items():
        parts = [x for x in p.split('/') if x]; node = tree
        for d in parts[:-1]: node = node.setdefault(d, {})
        node[parts[-1]] = v
    data = bytearray(); offs = {}
    def collect(node, prefix):
        for name in sorted(node, key=lambda x: x.lower(), reverse=(order == 'desc')):
            val = node[name]
            if isinstance(val, dict): collect(val, prefix + '/' + name)
            else: offs[id(val)] = 0x30 + len(data); data.extend(val[1])
    collect(tree, '')
    def entry(name, val):
        if isinstance(val, dict):
            out = struct.pack('<I', 0x20010) + _str(name) + struct.pack('<QQQ', FT, FT, FT) + struct.pack('<II', 0x20010, len(val))
            for n in sorted(val, key=lambda x: x.lower(), reverse=(order == 'desc')): out += entry(n, val[n])
            return out
        comp, raw, size = val
        return (struct.pack('<I', 0x20020) + _str(name) + struct.pack('<Q', offs[id(val)]) + struct.pack('<QQQ', FT, FT, FT)
                + struct.pack('<IIIII', 0x20020, 0, comp, len(raw), size))
    root = _str('') + struct.pack('<QQQ', FT, FT, FT) + struct.pack('<II', 0x20010, len(tree))
    for n in sorted(tree, key=lambda x: x.lower(), reverse=(order == 'desc')): root += entry(n, tree[n])
    root_off = 0x30 + len(data); end = root_off + len(root)
    hdr = struct.pack('<I4sIIII', 1, b'G3V0', 0, 0, 1, 0) + struct.pack('<QQQ', 0x30, root_off, end)
    with open(path, 'wb') as f: f.write(hdr); f.write(data); f.write(root)
def raw_entry(pak, key):
    p, off, comp, csz, sz = pak.files[key]; pak.f.seek(off); return (comp, pak.f.read(csz), sz)
def stored(b): return (0, bytes(b), len(b))
