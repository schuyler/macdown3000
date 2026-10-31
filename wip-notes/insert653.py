import re,glob,os,json,sys,shutil
ROOT=sys.argv[1]; D=sys.argv[2]
L=f'{ROOT}/MacDown/Localization'
def parse(p):
    return dict(re.findall(r'^"(.*?)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$',open(p,encoding='utf-8').read(),re.M))
def esc(s): return s.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')
problems=[]
for todo in sorted(glob.glob(f'{D}/*.todo.json')):
    loc=os.path.basename(todo)[:-10]
    t=json.load(open(todo)); done_p=f'{D}/{loc}.done.json'
    if not os.path.exists(done_p): problems.append(f'{loc}: no done file'); continue
    done=json.load(open(done_p))
    by_table={}
    for fk,item in t['missing'].items():
        table,key=fk.split('::',1)
        by_table.setdefault(table,[]).append((key,item))
    for table,items in by_table.items():
        p=f'{L}/{loc}.lproj/{table}.strings'
        existing=parse(p) if os.path.exists(p) else {}
        src=open(p,encoding='utf-8').read() if os.path.exists(p) else ''
        newvals={}
        for key,item in items:
            if 'same_as' not in item:
                v=done.get(f'{table}::{key}')
                if v is None or not str(v).strip(): problems.append(f'{loc} {table} {key}: missing translation'); continue
                newvals[key]=v
        for key,item in items:
            if 'same_as' in item:
                v=newvals.get(item['same_as'], existing.get(item['same_as']))
                if v is None: problems.append(f'{loc} {table} {key}: parent {item["same_as"]} untranslated'); continue
                newvals[key]=v
        out=src
        if out and not out.endswith('\n'): out+='\n'
        for key,item in items:
            if key not in newvals: continue
            if '.ibShadowedLabels' in key:
                c=f'/* Class = "{item["class"]}"; {key} = "{esc(item["english"])}"; ObjectID = "{item["id"]}"; */'
            else:
                c=f'/* Class = "{item["class"]}"; title = "{esc(item["english"])}"; ObjectID = "{item["id"]}"; */'
            out+=('\n' if out else '')+f'{c}\n"{key}" = "{esc(newvals[key])}";\n'
        open(p,'w',encoding='utf-8').write(out)
# ru-RU := uk for every table uk has
for p in glob.glob(f'{L}/uk.lproj/*.strings'):
    q=p.replace('/uk.lproj/','/ru-RU.lproj/')
    if os.path.exists(q): shutil.copyfile(p,q)
print('\n'.join(problems) if problems else 'no problems')
