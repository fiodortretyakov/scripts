import sys, collections, struct; sys.path.insert(0,'.'); from rpak import Pak; import tple, skills
R = r'C:\Program Files (x86)\Steam\steamapps\common\Risen\data'
SK = {0:'heal HP',1:'restore MP',2:'level',3:'XP',4:'LP',5:'max HP',6:'max MP',7:'STR',8:'DEX',9:'WIS',10:'prot blade',11:'prot blunt',12:'prot missile',13:'prot fire',14:'prot ice',15:'prot magic',16:'Sword',17:'Axe',18:'Staff',19:'Bow',20:'Crossbow',21:'Magic circle',22:'Fireball',23:'Frost',24:'Magic missile',25:'Smithing',29:'Sneak',30:'Acrobatics',31:'Alchemy',32:'Scribe'}
paks = [Pak(R + r'\common\templates.pak')] + [Pak(p) for p in sys.argv[1:]]
v, mods = paks[0], paks[1:]
import os
vbase = {os.path.basename(k): k for k in v.files}
guid = {}
for pk in paks:
    for k in pk.files:
        try: b = pk.read(k)
        except Exception: continue
        nm = pk.files[k][0].rsplit('/',1)[-1].replace('.tple',''); guid[b[0x1e:0x2e].hex()] = nm; guid[b[0x76:0x86].hex()] = nm
def fmt_sk(lists):
    return ' | '.join(', '.join(f"{SK.get(x.get('skill'), x.get('skill'))} {x.get('amt'):+d}" for x in arr) or '-' for arr in lists)
def fmt_ing(lists):
    return ' | '.join(', '.join(f"{x.get('amt')}x {guid.get(x.get('tpl'), x.get('tpl','?')[:8])}" for x in arr) or '-' for arr in lists)
NOISE = {'Guid','DocumentGuid','TimeStamp','Lightmaped','EnableRadiosity','CastDirLightShadows','CastPntLightShadows','CastStaticShadows','EnableCCD','SortValue','HoldOffset','Slots','',"Type"}
def scalars(b):
    out = collections.OrderedDict(); c = collections.Counter()
    for a, t, val in tple.props(b):
        if t == 'long' and isinstance(val, str) and len(val) == 8: val = struct.unpack('<i', bytes.fromhex(val))[0]
        if isinstance(val, str) and val.startswith('<'): continue
        out[(a, c[a])] = val; c[a] += 1
    return out
for mp in mods:
  print('######', mp.f.name)
  for k in sorted(mp.files):
    name = mp.files[k][0].rsplit('/',1)[-1].replace('.tple','')
    mb = mp.read(k); ms, me = tple.strtab(mb); msl = skills.skill_lists(mb, ms, me); msc = scalars(mb)
    vk = vbase.get(os.path.basename(k))
    if vk:
        vb = v.read(vk); vs, ve = tple.strtab(vb); vsl = skills.skill_lists(vb, vs, ve); vsc = scalars(vb); tag = 'CHG'
    else: vsl, vsc, tag = {}, {}, 'NEW'
    parts = []
    for p in ('RequiredSkills', 'ModifySkills'):
        a, bb = fmt_sk(vsl.get(p, [])), fmt_sk(msl.get(p, []))
        if a != bb: parts.append(f'{p}: [{a}] -> [{bb}]' if tag == 'CHG' else f'{p}: [{bb}]')
    a, bb = fmt_ing(vsl.get('CraftIngredients', [])), fmt_ing(msl.get('CraftIngredients', []))
    if a != bb: parts.append(f'Recipe: [{a}] -> [{bb}]' if tag == 'CHG' else f'Recipe: [{bb}]')
    for key in sorted(set(vsc) | set(msc), key=str):
        if key[0] in NOISE: continue
        x, y = vsc.get(key), msc.get(key)
        if x != y and (tag == 'CHG' or key[0] in ('GoldValue','Damage','DamageAmount','DamageType','Craft','ResultAmount','Category','UseType','MissionItem','Amount','Name')):
            parts.append(f'{key[0]}: {x} -> {y}' if tag == 'CHG' else f'{key[0]}={y}')
    print(f'{tag} {name}: ' + ('; '.join(parts) if parts else '(no gameplay change found)'))
