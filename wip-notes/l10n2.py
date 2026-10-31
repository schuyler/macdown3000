import re,sys,glob,os,collections
def keys_of(xib):
    src=open(xib).read(); keys={}
    for m in re.finditer(r'<(\w+)\b([^>]*?)\bid="([^"]+)"([^>]*)>',src):
        a=m.group(2)+m.group(4); t=re.search(r'\btitle="([^"]*)"',a)
        if t and t.group(1).strip(): keys[m.group(3)+'.title']=(m.group(1),t.group(1))
    for sid,body in re.findall(r'<segmentedCell\b[^>]*id="([^"]+)"[^>]*>(.*?)</segmentedCell>',src,re.S):
        for i,l in enumerate(re.findall(r'<segment\b([^>]*)',body)):
            lab=re.search(r'label="([^"]*)"',l)
            if lab and lab.group(1): keys[f'{sid}.ibShadowedLabels[{i}]']=('segment',lab.group(1))
    return keys
def parse(p):
    return dict(re.findall(r'^"(.*?)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$',open(p,encoding='utf-8').read(),re.M))
tot=0
for xib in sorted(glob.glob('MacDown/Localization/Base.lproj/*.xib')):
    name=os.path.basename(xib)[:-4]; keys=keys_of(xib)
    kinds=collections.Counter(k for k,_ in keys.values())
    miss=0; eng=0; per={}
    for p in sorted(glob.glob(f'MacDown/Localization/*.lproj/{name}.strings')):
        loc=p.split('/')[2][:-6]; d=parse(p)
        mm=[k for k in keys if k not in d]; miss+=len(mm); per[loc]=len(mm)
        eng+=sum(1 for k in keys if k in d and d[k]==keys[k][1])
    tot+=miss
    print(f'{name}: {len(keys)} keys {dict(kinds)}; tables={len(per)}; missing entries={miss}; english-valued={eng}')
    if len(sys.argv)>1: print('   ',per)
print('total missing',tot)
