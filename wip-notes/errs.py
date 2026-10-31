import sys,re
s=open(sys.argv[1]).read().replace('\\n','\n').replace('\\"','"').replace('\\u003c','<').replace('\\u003e','>')
for m in re.finditer(r'[^\n]*(\.m:\d+: error|Executed \d+ tests, with [1-9]\d* failures|NSLog|\*\* TEST|unrecognized selector|Failing tests)[^\n]*',s):
    t=m.group(0); print(t[:700])
i=s.find('Failing tests:'); print(s[i:i+800])
