import sys, os, re, struct, json; sys.path.insert(0,'.'); from rpak import Pak; import tple, wpak, infos
R = r'C:\Program Files (x86)\Steam\steamapps\common\Risen\data'; OUT = 'build'; os.makedirs(OUT + r'\common', exist_ok=True); os.makedirs(OUT + r'\compiled', exist_ok=True)
log = {}
def recs(b):
    s, end = tple.strtab(b); i = 0
    while i < end - 10:
        a, t, v = struct.unpack_from('<HHH', b, i)
        if v == 0x1e and a < len(s) and t < len(s):
            sz = struct.unpack_from('<I', b, i+6)[0]
            if 0 < sz < 1 << 24 and i + 10 + sz <= end:
                yield s[a], s[t], i + 10, sz
                i += 10 if s[t].startswith(('bTObjArray','bTValArray','bTRefPtrArray','bTPtrArray')) else 10 + sz; continue
        i += 1
def get_long(b, name):
    for n, t, off, sz in recs(b):
        if n == name and sz == 4: return off, struct.unpack_from('<i', b, off)[0]
    return None, None
# ---------------- templates ----------------
van = Pak(R + r'\common\templates.pak'); vbase = {os.path.basename(k): k for k in van.files}
M = r'mini\Risen Mini Mod Rerelease'; E = r'enh\data'; P = r'rip\Risen Improvements Pack Next-Gen\data'
final = {}
def put(pak, key, data=None, why=''):
    final[os.path.basename(key)] = (pak.files[key][0], wpak.stored(data) if data is not None else wpak.raw_entry(pak, key), why)
for pk in (Pak(M + r'\common\templates.p00'), Pak(M + r'\common\templates.p02')):
    for k in pk.files: put(pk, k, why='Mini')
enh = Pak(E + r'\common\templates.p00')
lines = {re.match(r'(?:CHG|NEW) (\S+):', l).group(1).lower(): l for l in open('enh_templates.txt', encoding='utf-8') if re.match(r'(CHG|NEW) ', l)}
SKIP_ENH = {'it_blackpearl','it_goldore','it_pearl','it_recipe_hp_max','it_recipe_mp_max','it_smithhammer','it_stoneplate'}
for k in enh.files:
    name = os.path.basename(k)[:-5].lower(); l = lines.get(name, '')
    body = l.split(': ', 1)[1] if ': ' in l else ''
    if name in SKIP_ENH or 'no gameplay change' in body: continue
    if re.fullmatch(r'GoldValue: -?\d+ -> -?\d+\s*', body): continue   # price-only change: keep vanilla
    b = bytearray(enh.read(k)); vk = vbase.get(os.path.basename(k))
    if vk:
        off, val = get_long(b, 'GoldValue'); _, vval = get_long(van.read(vk), 'GoldValue')
        if off is not None and vval is not None and val != vval: struct.pack_into('<i', b, off, vval)
    put(enh, k, bytes(b), why='Enhanced')
for name in ('it_recipe_hp_max.tple', 'it_recipe_mp_max.tple'):
    final.pop(name, None)    # Mini's 3-berry recipes removed: vanilla 10 berries
for f in (P + r'\common\templates.p00', P + r'\common\templates.p01'):
    pk = Pak(f)
    for k in pk.files:
        if os.path.basename(k) in ('it_plant_speed.tple', 'it_po_mana_02.tple', 'it_po_mana_03.tple'): put(pk, k, why='Improvements')
icf = Pak(r'mega\FanMods\I_Can_Fight_With_These\common\templates.p0x')
for k in icf.files: put(icf, k, why='I Can Fight With These')
nmon = 0
for k in van.files:
    if not k.startswith('/monster/') or '/special/' in k or os.path.basename(k).startswith('it_') or '_head' in k: continue
    if os.path.basename(k) in final: continue
    b = bytearray(van.read(k))
    for n, t, off, sz in recs(b):
        if n == 'DamageMultiplier' and t == 'float' and abs(struct.unpack_from('<f', b, off)[0] - 1.0) < 1e-6:
            struct.pack_into('<f', b, off, 1.25); put(van, k, bytes(b), why='monster x1.25'); nmon += 1; break
# sprint instead of walking: hero walk-mode speed 0.375 -> 1.5 (removed 7 Oct, restored same day on request)
hk = [k for k in van.files if k.endswith('/pc_hero.tple')][0]; hb = bytearray(van.read(hk)); nsl = 0
for n, t, off, sz in recs(bytes(hb)):
    if n == 'SlowModifier' and t == 'float' and abs(struct.unpack_from('<f', hb, off)[0] - 0.375) < 1e-6:
        struct.pack_into('<f', hb, off, 1.5); nsl += 1
assert nsl == 1, nsl
put(van, hk, bytes(hb), why='sprint 1.5')
wpak.write(OUT + r'\common\templates.p00', {p: e for p, e, w in final.values()})
from collections import Counter; log['templates'] = dict(Counter(w for p, e, w in final.values())); log['monsters_patched'] = nmon
# ---------------- projects (world) ----------------
proj = {}
for f in (M + r'\common\projects.p00', M + r'\common\projects.p01'):
    pk = Pak(f)
    for k in pk.files: proj[k] = (pk.files[k][0], wpak.raw_entry(pk, k))
ep = Pak(E + r'\common\projects.p00')
for k in ep.files:
    if k not in proj: proj[k] = (ep.files[k][0], wpak.raw_entry(ep, k)); log.setdefault('world_from_enhanced', []).append(ep.files[k][0])
wpak.write(OUT + r'\common\projects.p00', dict(proj.values())); log['world_files'] = len(proj)
# ---------------- library ----------------
m0 = Pak(M + r'\compiled\library.p00'); m1 = Pak(M + r'\compiled\library.p01')
inf = bytearray(m1.read('/compiled_infos.bin')); qst = bytearray(m0.read('/compiled_quests.bin'))
COMBAT = {'Sword','Axe','Staff','Bow','Crossbow','Fireball','Frost','Missile','Circle'}; OTHER = {'Smithing','Alchemy','Scribe','Sneak','Acrobatics','s26','s27','s28','s33'}
cur = None; last = None; changes = Counter(); s, end = tple.strtab(bytes(inf)); pending = []
for n, t, off, sz in recs(bytes(inf)):
    if n == 'MainSortID' and last == 'Name': cur = {'lp': None, 'teach': []}; pending.append(cur)
    if cur is not None:
        if n == 'LearnPointCost' and sz == 4 and cur['lp'] is None: cur['lp'] = off
        elif n == 'TeachSkill': cur['teach'].append(infos.skillval(bytes(inf[off:off+sz]), s)[0])
    last = n
for c in pending:
    if c['lp'] is None or not c['teach']: continue
    lp = struct.unpack_from('<i', inf, c['lp'])[0]; sk = set(c['teach'])
    new = None
    if sk <= COMBAT | {'s26'} and lp == 10: new = 7
    elif sk <= COMBAT | OTHER and lp == 5: new = 4
    if new: struct.pack_into('<i', inf, c['lp'], new); changes[f'{"/".join(sorted(sk))} {lp}->{new}'] += 1
log['lp_changes'] = dict(changes)
tot0 = tot1 = 0
for n, t, off, sz in recs(bytes(qst)):
    if n == 'ExperiencePoints' and sz == 4:
        x = struct.unpack_from('<i', qst, off)[0]; y = int(round(x * 1.5)); struct.pack_into('<i', qst, off, y); tot0 += x; tot1 += y
log['quest_xp'] = (tot0, tot1)
lib = {'/compiled_infos.bin': wpak.stored(inf), '/compiled_quests.bin': wpak.stored(qst), '/compiled_combatspecies.bin': wpak.raw_entry(m0, '/compiled_combatspecies.bin')}
wpak.write(OUT + r'\compiled\library.p00', lib)
# ---------------- images (Mini + Enhanced armour/nudity) ----------------
img = {}
mi = Pak(M + r'\compiled\images.p00')
for k in mi.files: img[mi.files[k][0]] = wpak.raw_entry(mi, k)
ei = Pak(E + r'\compiled\images.p00')
for k in ei.files:
    if 'head_hero' not in k: img[ei.files[k][0]] = wpak.raw_entry(ei, k)
wpak.write(OUT + r'\compiled\images.p01', img); log['images'] = len(img)
json.dump(log, open(OUT + r'\build_log.json', 'w'), indent=1); print(json.dumps(log, indent=1))
