#!/bin/bash
set -euo pipefail
source /workspace/toolchains/luno-env.sh
cd /workspace/luno-chess/luno_chess
request_file=$(mktemp /tmp/round3-rules-stdin.XXXXXX)
trap 'rm -f "$request_file"' EXIT
cat > "$request_file"
dart --packages=.dart_tool/package_config.json tool/battle_json_runner.dart < "$request_file"
