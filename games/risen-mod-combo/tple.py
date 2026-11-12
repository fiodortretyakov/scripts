import struct
def strtab(b):
    m = b.rfind(b'\xef\xbe\xad\xde'); n = struct.unpack_from('<I', b, m+5)[0]; i = m+9; s = []
    for _ in range(n):
        L = struct.unpack_from('<H', b, i)[0]; s.append(b[i+2:i+2+L].decode('latin1')); i += 2+L
    return s, m
def props(b):
    s, end = strtab(b); n = len(s); out = []; i = 0
    while i < end - 10:
        a, t, v = struct.unpack_from('<HHH', b, i)
        if v == 0x1e and a < n and t < n:
            sz = struct.unpack_from('<I', b, i+6)[0]; ty = s[t]
            if 0 < sz < 4096 and i + 10 + sz <= end and (ty in ('int','float','bool','bCString','char','short','long','bCVector','bCGuid','bCFloatColor','bCEulerAngles') or ty.startswith(('bTPropertyContainer','bTValArray','bTObjArray','gE','eE','bE','bTPropertyObject','bTRefPtrArray'))):
                raw = b[i+10:i+10+sz]
                if ty == 'int' and sz == 4: val = struct.unpack('<i', raw)[0]
                elif ty == 'float' and sz == 4: val = round(struct.unpack('<f', raw)[0], 4)
                elif ty == 'bool' and sz == 1: val = bool(raw[0])
                elif ty == 'bCString' and sz == 2: val = s[struct.unpack('<H', raw)[0]] if struct.unpack('<H', raw)[0] < n else raw.hex()
                elif ty.startswith('bTPropertyContainer') and sz == 6: val = struct.unpack_from('<I', raw, 2)[0]
                else: val = raw.hex() if sz <= 24 else f'<{sz} bytes>'
                out.append((s[a], ty, val)); i += 10 + sz; continue
        i += 1
    return out
