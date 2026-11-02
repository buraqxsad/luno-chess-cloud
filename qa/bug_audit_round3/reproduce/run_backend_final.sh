#!/usr/bin/env bash
source /workspace/toolchains/luno-env.sh
luno_round_dir=/workspace/luno-review/bug-audit-round3
cd /workspace/luno-chess/functions
npm run build:battle > "$luno_round_dir/typescript-build.log" 2>&1
luno_build_rc=$?
printf '%s\n' "$luno_build_rc" > "$luno_round_dir/typescript-build-exit.txt"
if [ "$luno_build_rc" -ne 0 ]; then exit "$luno_build_rc"; fi
python3 "$luno_round_dir/run_node_direct.py" backend > "$luno_round_dir/backend-full.log" 2>&1
luno_backend_rc=$?
printf '%s\n' "$luno_backend_rc" > "$luno_round_dir/backend-full-exit.txt"
if [ "$luno_backend_rc" -ne 0 ]; then exit "$luno_backend_rc"; fi
cd /workspace/luno-chess/functions/rules-v1
npm run typecheck > "$luno_round_dir/typescript-typecheck.log" 2>&1
luno_type_rc=$?
printf '%s\n' "$luno_type_rc" > "$luno_round_dir/typescript-typecheck-exit.txt"
if [ "$luno_type_rc" -ne 0 ]; then exit "$luno_type_rc"; fi
export LUNO_DART_RUNNER=/workspace/luno-review/system-bug-hunt/differential/battle-json-runner
export LUNO_DART_RUNNER_ARGS='[]'
export LUNO_DIFFERENTIAL_QA="$luno_round_dir/differential"
python3 "$luno_round_dir/run_node_direct.py" typescript > "$luno_round_dir/typescript-full.log" 2>&1
luno_ts_rc=$?
printf '%s\n' "$luno_ts_rc" > "$luno_round_dir/typescript-full-exit.txt"
if [ "$luno_ts_rc" -ne 0 ]; then exit "$luno_ts_rc"; fi
python3 - <<'PY'
from pathlib import Path
import json,hashlib,subprocess
repo=Path('/workspace/luno-chess');r=Path('/workspace/luno-review/bug-audit-round3');p=json.loads(Path('/workspace/luno-review/bug-audit-round2/differential/source-provenance.json').read_text())
for name,expected in p['inputs_sha256'].items():assert hashlib.sha256((repo/name).read_bytes()).hexdigest()==expected,name
assert hashlib.sha256(Path(p['runner_reused_from']).read_bytes()).hexdigest()==p['runner_sha256']
p['current_source_commit']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip();p['revalidated_before_current_run']=True
(r/'differential/source-provenance.json').write_text(json.dumps(p,indent=2)+'\n')
PY
if [ "$?" -ne 0 ]; then exit 2; fi
node dist/test/differential.js > "$luno_round_dir/differential/full.log" 2>&1
luno_diff_rc=$?
printf '%s\n' "$luno_diff_rc" > "$luno_round_dir/differential/exit.txt"
exit "$luno_diff_rc"
