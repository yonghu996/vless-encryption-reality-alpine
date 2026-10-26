#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n install.sh
source ./install.sh
command -v jq >/dev/null
inbound=$(build_standard_inbound 12774 11111111-2222-4333-8444-555555555555 bing.com 20220701 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA)
printf '%s\n' "$inbound" | jq -e '
 .settings.decryption == "none"
 and .settings.clients[0].flow == "xtls-rprx-vision"
 and .streamSettings.security == "reality"
 and .port == 12774
' >/dev/null
if printf '%s\n' "$inbound" | grep -q mlkem768x25519plus; then exit 1; fi
if printf '%s\n' "$inbound" | jq -e '.settings | has("encryption")' >/dev/null; then exit 1; fi
echo "PASS standard VLESS inbound config is sing-box compatible"
