import re,sys,glob,os
xib=sys.argv[1]; table=os.path.basename(xib).replace('.xib','.strings')
src=open(xib).read()
# objects with title/label attributes
keys={}
for m in re.finditer(r'<(\w+)\b([^>]*?)\bid="([^"]+)"([^>]*)>',src):
    attrs=m.group(2)+m.group(4)
    for a in ['title','placeholderString','label']:
        t=re.search(r'\b%s="([^"]*)"'%a,attrs)
        if t and t.group(1).strip(): keys[f'{m.group(3)}.{a}']=t.group(1)
# segment labels
for m in re.finditer(r'<segmentedControl\b[^>]*id="([^"]+)"',src):
    pass
seg=re.findall(r'<segmentedCell\b[^>]*id="([^"]+)"[^>]*>(.*?)</segmentedCell>',src,re.S)
for sid,body in seg:
    for i,l in enumerate(re.findall(r'<segment\b([^>]*)',body)):
        lab=re.search(r'label="([^"]*)"',l)
        if lab: keys[f'{sid}.ibShadowedLabels[{i}]']=lab.group(1)
def parse(p):
    d={}
    for k,v in re.findall(r'^"(.*?)"\s*=\s*"(.*)";\s*$',open(p,encoding='utf-8',errors='replace').read(),re.M): d[k]=v
    return d
print(len(keys),"keys in xib")
for p in sorted(glob.glob(f'MacDown/Localization/*.lproj/{table}')):
    loc=p.split('/')[2].replace('.lproj','')
    d=parse(p)
    missing=[k for k in keys if k not in d]
    english=[k for k in keys if k in d and d[k]==keys[k]]
    extra=[k for k in d if k not in keys]
    print(loc,"missing:",missing,"\n   english:",english,"\n   stale:",extra)
