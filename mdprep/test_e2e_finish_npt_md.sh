#!/usr/bin/env bash
# EM+NVT bittikten sonra NPT+MD (10 ps) gönder ve bekle
set -o errexit -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${MDPREP_DIR}/.." && pwd)"
cd "${ROOT}"
source "${MDPREP_DIR}/lib/common.sh"

export MDQUEUE_MDPREP_DIR="${MDPREP_DIR}"
export MDQUEUE_WORKDIR="${ROOT}"
export MDQUEUE_STATE_DIR="${STATE_DIR}"
export MDQUEUE_JOBS_FILE="${STATE_DIR}/jobs.json"
export MDQUEUE_LOG_DIR="${LOG_DIR}/queue"

PY="${MDPREP_DIR}/.venv/bin/python3"
[[ -x "${PY}" ]] || PY="$(command -v python3)"

require_file nvt.gro "nvt.gro (önce NVT bitmeli)"

printf 'y\n' | "${PY}" "${MDPREP_DIR}/lib/md_queue.py" submit npt
NPT_JOB="$("${PY}" -c "
import json
j=json.load(open('${STATE_DIR}/jobs.json'))
ids=[x['job_id'] for x in j if x.get('phase')=='npt' and x.get('status')=='Running']
print(ids[-1] if ids else [x['job_id'] for x in j if x.get('phase')=='npt'][-1])
")"
echo "NPT job: ${NPT_JOB}"
printf 'y\n' | "${PY}" "${MDPREP_DIR}/lib/md_queue.py" submit md --wait-for "${NPT_JOB}"

"${PY}" "${MDPREP_DIR}/lib/md_queue.py" wait-all
bash "${MDPREP_DIR}/test_e2e_10ps.sh" --audit-only
bash "${MDPREP_DIR}/lib/analyze_md.sh" all
bash "${MDPREP_DIR}/lib/sync_mdp.sh" --fix
echo "E2E_10PS_DONE $(date -Iseconds)" >> "${MDPREP_DIR}/logs/e2e_10ps_run.log"
