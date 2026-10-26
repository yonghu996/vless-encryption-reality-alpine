#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n install.sh
bash -n tests/test_reality_keys.sh
grep -F 'tmp_config="${tmp_config}.json"' install.sh >/dev/null
grep -F 'run -test -format=json -config "$tmp_config"' install.sh >/dev/null
printf 'PASS: temporary config ends in .json and syntax is valid\n'
