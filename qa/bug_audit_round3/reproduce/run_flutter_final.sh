#!/usr/bin/env bash
source /workspace/toolchains/luno-env.sh
cd /workspace/luno-chess/luno_chess
python3 - <<'PY'
import json,pathlib,subprocess
repo=pathlib.Path('/workspace/luno-chess');r=pathlib.Path('/workspace/luno-review/bug-audit-round3')
s=json.loads((r/'source-commit.json').read_text())
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()==s['full_regression_source_commit']
assert subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True).strip()==''
PY
if [ "$?" -ne 0 ]; then exit 2; fi
flutter analyze --no-pub > /workspace/luno-review/bug-audit-round3/analyze-final.log 2>&1
luno_analyze_exit=$?
printf '%s\n' "$luno_analyze_exit" > /workspace/luno-review/bug-audit-round3/analyze-final-exit.txt
if [ "$luno_analyze_exit" -ne 0 ]; then exit "$luno_analyze_exit"; fi
flutter test --no-pub --concurrency=2 --reporter=json > /workspace/luno-review/bug-audit-round3/flutter/full.jsonl 2> /workspace/luno-review/bug-audit-round3/flutter/full-stderr.log
printf '%s\n' "$?" > /workspace/luno-review/bug-audit-round3/flutter/full-exit.txt
python3 /workspace/luno-review/bug-audit-round3/summarize.py --collect > /workspace/luno-review/bug-audit-round3/flutter/summary-collection.log 2>&1
printf '%s\n' "$?" > /workspace/luno-review/bug-audit-round3/flutter/collection-exit.txt
