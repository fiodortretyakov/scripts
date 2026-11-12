import sys, struct; sys.path.insert(0,'.'); import tple
SK = {0:'heal HP',1:'restore MP',2:'level',3:'XP',4:'LP',5:'HP',6:'MP',7:'STR',8:'DEX',9:'WIS',16:'Sword',17:'Axe',18:'Staff',19:'Bow',20:'Crossbow',21:'Circle',22:'Fireball',23:'Frost',24:'Missile',25:'Smithing',26:'s26',27:'s27',28:'s28',29:'Sneak',30:'Acrobatics',31:'Alchemy',32:'Scribe',33:'s33'}
def skillval(raw, s):
    amt = sk = None; j = 0
    while j < len(raw) - 10:
        a, t, v = struct.unpack_from('<HHH', raw, j)
        if v == 0x1e and a < len(s) and t < len(s):
            sz = struct.unpack_from('<I', raw, j+6)[0]; d = raw[j+10:j+10+sz]
            if s[a] == 'Amount': amt = struct.unpack('<i', d[:4])[0]
            elif s[a] == 'Skill': sk = struct.unpack_from('<I', d, 2)[0]
            j += 10 + sz; continue
        j += 1
    return (SK.get(sk, sk), amt)
def parse(path):
    b = open(path,'rb').read(); s, end = tple.strtab(b); infos = {}; cur = None; i = 0; last = None
    while i < end - 10:
        a, t, v = struct.unpack_from('<HHH', b, i)
        if v == 0x1e and a < len(s) and t < len(s):
            sz = struct.unpack_from('<I', b, i+6)[0]; raw = b[i+10:i+10+sz]; nm, ty = s[a], s[t]
            if nm == 'MainSortID' and last and last[0] == 'Name':
                cur = {'teach': [], 'cond': []}; infos[last[1]] = cur
            if ty == 'bCString' and sz == 2: val = s[struct.unpack('<H', raw)[0]]
            elif ty in ('long','int') and sz == 4: val = struct.unpack('<i', raw)[0]
            elif ty.startswith('bTPropertyContainer') and sz == 6: val = struct.unpack_from('<I', raw, 2)[0]
            else: val = None
            if cur is not None:
                if nm in ('Owner','GoldCost','LearnPointCost','Quest','Type'): cur[nm] = val
                elif nm == 'TeachSkill': cur['teach'].append(skillval(raw, s))
                elif nm == 'CompareOperation': cur['cond'].append([val])
                elif nm == 'SkillValue' and cur['cond']: cur['cond'][-1].append(skillval(raw, s))
            last = (nm, val)
            i += 10 if ty.startswith(('bTObjArray','bTValArray','bTRefPtrArray','bTPtrArray')) else 10 + sz; continue
        i += 1
    return infos
