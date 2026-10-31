#!/bin/bash
# usage: waitci.sh <sha>  -- waits until all check runs complete; prints summary
sha=$1
sleep 90
while true; do
  out=$(curl -s "https://api.github.com/repos/schuyler/macdown3000/commits/$sha/check-runs?per_page=50" | python3 -c "
import json,sys
d=json.load(sys.stdin); runs=d.get('check_runs',[])
pend=[r['name'] for r in runs if r['status']!='completed']
print(len(runs), len(pend)); [print(r['name'],r['status'],r['conclusion']) for r in runs]")
  n=$(echo "$out"|head -1|cut -d' ' -f1); p=$(echo "$out"|head -1|cut -d' ' -f2)
  if [ "$n" -gt 0 ] && [ "$p" = 0 ]; then echo "$out"; exit 0; fi
  sleep 60
done
