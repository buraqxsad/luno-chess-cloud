#!/usr/bin/env bash
while [ ! -f /workspace/luno-review/bug-audit-round2/generated/collection.json ]; do sleep 5; done
source /workspace/toolchains/luno-env.sh
python3 /workspace/luno-review/bug-audit-round2/post_tests.py || exit "$?"
while [ ! -f /workspace/luno-review/bug-audit-round2/backend-full-exit.txt ]; do sleep 2; done
flock /workspace/luno-review/bug-audit-round2/flutter.lock python3 /workspace/luno-review/bug-audit-round2/android/build_android.py
printf '%s\n' "$?" > /workspace/luno-review/bug-audit-round2/android/pipeline-exit.txt
