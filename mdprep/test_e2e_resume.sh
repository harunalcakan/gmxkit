#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
ROOT="/mnt/c/Users/zenbook/Desktop/native_ca1_test_cursor"
cd "${ROOT}"
source mdprep/lib/common.sh

PS=2500
EM=5000
sed -i -E "s/^nsteps[[:space:]]*=.*/nsteps                  = ${EM}/" em.mdp
for f in nvt.mdp npt.mdp md.mdp; do
  sed -i -E "s/^nsteps[[:space:]]*=.*/nsteps                  = ${PS}/" "${f}"
done
echo "=== MDP nsteps ==="
grep '^nsteps' em.mdp nvt.mdp npt.mdp md.mdp

printf 'y\n' | bash mdprep/lib/job_queue.sh chain

PY="mdprep/.venv/bin/python3"
[[ -x "${PY}" ]] || PY="python3"
while true; do
  "${PY}" mdprep/lib/md_queue.py status >/dev/null 2>&1 || true
  running=$("${PY}" -c "
import json, os
p='mdprep/.state/jobs.json'
if not os.path.exists(p): print(0); raise SystemExit
print(sum(1 for x in json.load(open(p)) if x.get('status')=='Running'))
")
  echo "Running: ${running}"
  [[ "${running}" -eq 0 ]] && break
  sleep 20
done

bash mdprep/test_e2e_5ps.sh --audit-only 2>/dev/null || true
