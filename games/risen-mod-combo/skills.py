import struct
def skill_lists(b, s, end):
    """Return {propName: [(skill, amount), ...]} for gCSkillValue/gCModifySkill arrays (in order)."""
    res = {}; i = 0
    while i < end - 10:
        a, t, ver = struct.unpack_from('<HHH', b, i)
        if ver == 0x1e and a < len(s) and t < len(s) and s[t].startswith('bTObjArray<class gC') and ('Skill' in s[t] or 'CraftIngredient' in s[t]):
            sz = struct.unpack_from('<I', b, i+6)[0]; raw = b[i+10:i+10+sz]; items = []; cur = {}
            j = 0
            while j < len(raw) - 10:
                a2, t2, v2 = struct.unpack_from('<HHH', raw, j)
                if v2 == 0x1e and a2 < len(s) and t2 < len(s):
                    sz2 = struct.unpack_from('<I', raw, j+6)[0]; d = raw[j+10:j+10+sz2]; nm = s[a2]
                    if nm in ('Amount', 'ItemAmount'): cur['amt'] = struct.unpack('<i', d[:4])[0]
                    elif nm == 'Skill': cur['skill'] = struct.unpack_from('<I', d, 2)[0]
                    elif nm == 'ItemTemplate': cur['tpl'] = d[3:19].hex()
                    if len(cur) == 2: items.append(cur); cur = {}
                    j += 10 + sz2; continue
                j += 1
            res.setdefault(s[a], []).append(items); i += 10 + sz; continue
        i += 1
    return res
