#!/usr/bin/env bash
while [ ! -f /workspace/luno-review/bug-audit-round4/generated/collection.json ]; do
  for luno_gate in analyze-final-exit.txt flutter/collection-exit.txt; do
    if [ -f "/workspace/luno-review/bug-audit-round4/$luno_gate" ] && [ "$(cat "/workspace/luno-review/bug-audit-round4/$luno_gate")" != 0 ]; then exit 2; fi
  done
  sleep 3
done
source /workspace/toolchains/luno-env.sh
python3 /workspace/luno-review/bug-audit-round4/post_tests.py || exit "$?"
for luno_final_gate in backend-full-exit.txt typescript-full-exit.txt differential/exit.txt; do
  while [ ! -f "/workspace/luno-review/bug-audit-round4/$luno_final_gate" ]; do sleep 2; done
  if [ "$(cat "/workspace/luno-review/bug-audit-round4/$luno_final_gate")" != 0 ]; then exit 3; fi
done
flock /workspace/luno-review/bug-audit-round4/flutter.lock python3 /workspace/luno-review/bug-audit-round4/android/build_android.py
luno_android_rc=$?
printf '%s\n' "$luno_android_rc" > /workspace/luno-review/bug-audit-round4/android/pipeline-exit.txt
exit "$luno_android_rc"
