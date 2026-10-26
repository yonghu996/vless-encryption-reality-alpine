#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n install.sh
bash -n tests/test_reality_keys.sh
bash -n tests/test_config_temp_suffix.sh
grep -F 'prepare_xray_log_permissions() {' install.sh >/dev/null
grep -F 'if ! prepare_xray_log_permissions; then return 1; fi' install.sh >/dev/null
grep -F 'chown root:xray "$tmp_config"' install.sh >/dev/null
grep -F 'su -s /bin/sh -c' install.sh >/dev/null
grep -F 'install -m 600 -o xray -g xray /dev/null "$log_file"' install.sh >/dev/null
grep -F '"domainStrategy": "UseIPv4v6"' install.sh >/dev/null
echo "PASS: log permissions, service-user validation, syntax"
