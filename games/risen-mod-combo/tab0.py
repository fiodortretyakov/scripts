import struct
def parse(d):
    assert d[:4] == b'TAB0'; i = 16; ncol = struct.unpack_from('<I', d, i)[0]; i += 4; cols = []
    for _ in range(ncol):
        i += 3; L = struct.unpack_from('<H', d, i)[0]; i += 2; name = d[i:i+2*L].decode('utf-16-le'); i += 2*L
        n = struct.unpack_from('<I', d, i)[0]; i += 4; vals = []
        for _ in range(n):
            L = struct.unpack_from('<H', d, i)[0]; i += 2; vals.append(d[i:i+2*L].decode('utf-16-le', 'replace')); i += 2*L
        cols.append((name, vals))
    return cols, i
