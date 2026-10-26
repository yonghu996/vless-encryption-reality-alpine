#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ./install.sh
is_quiet=true
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
xray_binary_path="$tmp/xray"
cat > "$xray_binary_path" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  x25519)
    case "${XRAY_MOCK_CASE:-new}" in
      new)
        printf 'PrivateKey: %043d\nPassword (PublicKey): %043d\nHash32: %043d\n' 0 1 2 ;;
      old)
        printf 'PrivateKey: %043d\nPassword: %043d\n' 0 1 ;;
      legacy)
        printf 'Private key: %043d\nPublic key: %043d\n' 0 1 ;;
      missing)
        printf 'PrivateKey: %043d\nHash32: %043d\n' 0 2 ;;
      short)
        printf 'PrivateKey: abc\nPassword (PublicKey): xyz\n' ;;
      fail) exit 3 ;;
    esac
    ;;
  *) exit 4 ;;
esac
MOCK
chmod +x "$xray_binary_path"
for mode in new old legacy; do
  export XRAY_MOCK_CASE="$mode"
  output=$(generate_reality_keys)
  [[ "$output" == "$(printf '%043d' 0)|$(printf '%043d' 1)" ]] || { echo "FAIL: $mode"; exit 1; }
  echo "PASS: $mode key labels"
done
for mode in missing short fail; do
  export XRAY_MOCK_CASE="$mode"
  if generate_reality_keys >/dev/null 2>&1; then echo "FAIL: unexpected success for $mode"; exit 1; fi
  echo "PASS: rejects $mode"
done
echo "REALITY KEY PARSER TESTS PASSED"
