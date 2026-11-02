#!/usr/bin/env bash
set -u
source /workspace/toolchains/luno-env.sh
cd /workspace/luno-chess/luno_chess
exec 9>/workspace/luno-review/bug-audit-round4/flutter.lock
flock 9
audit_dir=/workspace/luno-review/bug-audit-round4/client
cp lib/models/game_store.dart "$audit_dir/game_store.fixed.dart"
trap 'cp "$audit_dir/game_store.fixed.dart" lib/models/game_store.dart' EXIT
git show d67cd449cbd8834a4878f5484941d376fa7c17d8:luno_chess/lib/models/game_store.dart > lib/models/game_store.dart
sha256sum lib/models/game_store.dart test/round4_client_recovery_durability_test.dart > "$audit_dir/canonical-before-source-hashes.txt"
flutter test --no-pub --concurrency=1 --reporter expanded --name '^(?!.*(backup_pending_v1|pending-marker)).*$' test/round4_client_recovery_durability_test.dart > "$audit_dir/canonical-before.log" 2>&1
run_exit=$?
printf '%s\n' "$run_exit" > "$audit_dir/canonical-before.exit"
cp "$audit_dir/game_store.fixed.dart" lib/models/game_store.dart
sha256sum lib/models/game_store.dart test/round4_client_recovery_durability_test.dart > "$audit_dir/fixed-restored-source-hashes.txt"
tail -35 "$audit_dir/canonical-before.log"
exit "$run_exit"
