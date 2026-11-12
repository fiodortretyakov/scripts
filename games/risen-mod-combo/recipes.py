import sys, os, struct; sys.path.insert(0,'.'); from rpak import Pak; import tple, skills, tab0
R = r'C:\Program Files (x86)\Steam\steamapps\common\Risen\data'
van = Pak(R + r'\common\templates.pak'); bld = Pak(r'build\common\templates.p00')
vb = {os.path.basename(k): k for k in van.files}
guid = {}
for pk in (bld, van):
    for k in pk.files:
        d = pk.read(k); n = os.path.basename(k)[:-5].lower()
        for o in (0x76, 0x1e): guid.setdefault(d[o:o+16].hex(), n)
        j = 0
        while True:
            j = d.find(b'\xdb\x00', j, 0x140)
            if j < 0: break
            guid.setdefault(d[j+2:j+18].hex(), n); j += 2
cols, _ = tab0.parse(Pak(r'ru\strings.p02').read('/focus.tab')); ids = cols[0][1]; c = dict(cols)
ru = {ids[i][3:].lower(): c['Russian_Text'][i] or c['English_Text'][i] for i in range(len(ids)) if ids[i].startswith('FO_')}
SK = {25: 'Кузнечное дело', 31: 'Алхимия', 32: 'Письмо', 21: 'Круг', 9: 'Мудрость', 7: 'Сила'}
def info(d):
    s, end = tple.strtab(d); sl = skills.skill_lists(d, s, end); res = None; i = 0
    while i < end - 10:
        a, t, v = struct.unpack_from('<HHH', d, i)
        if v == 0x1e and a < len(s) and t < len(s) and s[a] == 'ResultItem': res = guid.get(d[i+13:i+29].hex()); break
        i += 1
    ing = [(x.get('amt'), guid.get(x.get('tpl'), '?')) for arr in sl.get('CraftIngredients', []) for x in arr]
    req = [(x['skill'], x['amt']) for arr in sl.get('RequiredSkills', [])[1:] for x in arr]
    return res, ing, req
nm = lambda t: ru.get(t or '', t or '?')
for k in sorted(bld.files):
    base = os.path.basename(k); name = base[:-5].lower(); d = bld.read(k)
    res, ing, req = info(d)
    if not ing or name.endswith(('_hot', '_shaped', '_dull')): continue
    old = info(van.read(vb[base])) if base in vb else None
    if old and old[1] == ing and old[2] == req: continue
    st = 'NEW' if not old or not old[1] else 'CHG'
    final = name[:-7] if name.endswith('_recipe') else (res or name)
    reqs = ', '.join(f"{SK.get(a, a)} {b}" for a, b in req) or '-'
    was = '' if st == 'NEW' else ' | было: ' + ', '.join(f"{a}× {nm(t)}" for a, t in old[1]) + (f" ({', '.join(f'{SK.get(a, a)} {b}' for a, b in old[2]) or '-'})")
    print(f"{st} | {nm(final)} | {', '.join(f'{a}× {nm(t)}' for a, t in ing)} | {reqs}{was} | {name}")
