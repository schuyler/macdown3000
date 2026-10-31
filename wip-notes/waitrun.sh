#!/bin/bash
# usage: waitrun.sh <branch> -- waits for latest test.yml dispatch run on branch; prints job results
b=$1; sleep 60
while true; do
  id=$(curl -s "https://api.github.com/repos/schuyler/macdown3000/actions/workflows/test.yml/runs?branch=$b&per_page=1" | python3 -c "import json,sys; r=json.load(sys.stdin)['workflow_runs']; print(r[0]['id'] if r else '')")
  if [ -n "$id" ]; then
    st=$(curl -s https://api.github.com/repos/schuyler/macdown3000/actions/runs/$id | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
    if [ "$st" = completed ]; then
      curl -s https://api.github.com/repos/schuyler/macdown3000/actions/runs/$id/jobs | python3 -c "
import json,sys
for j in json.load(sys.stdin)['jobs']: print('$b', j['id'], j['name'], j['conclusion'])"; exit 0; fi
  fi
  sleep 60
done
