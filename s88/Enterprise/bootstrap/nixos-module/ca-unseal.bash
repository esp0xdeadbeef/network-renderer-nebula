set -euo pipefail

state_dir="/persist/nebula-runtime"
pki_dir="$state_dir/pki"
run_dir="/run/nebula-runtime"
unsealed_dir="$run_dir/unsealed"
passphrase_file="/run/keys/nebula-ca-passphrase"
legacy_ca_key="$pki_dir/ca.key"
encrypted_ca_key="$pki_dir/ca.key.enc"
ca_crt="$pki_dir/ca.crt"
unsealed_ca_key="$unsealed_dir/ca.key"
tmpdir=""

cleanup() {
  rm -f "$passphrase_file"
  if [ -n "$tmpdir" ] && [ -d "$tmpdir" ]; then
    rm -rf "$tmpdir"
  fi
}
trap cleanup EXIT

if [ ! -s "$passphrase_file" ]; then
  echo "nebula-ca-unseal: missing transient passphrase file $passphrase_file" >&2
  exit 1
fi

install -d -m 0700 "$pki_dir" "$run_dir" "$unsealed_dir"

seal_plaintext_key() {
  local plaintext_key="$1"

  openssl enc -aes-256-cbc -pbkdf2 -salt \
    -in "$plaintext_key" \
    -out "$encrypted_ca_key" \
    -pass "file:$passphrase_file"
  chmod 0600 "$encrypted_ca_key"

  if command -v shred >/dev/null 2>&1; then
    shred -u "$plaintext_key" 2>/dev/null || rm -f "$plaintext_key"
  else
    rm -f "$plaintext_key"
  fi
}

if [ -s "$legacy_ca_key" ]; then
  if [ ! -s "$encrypted_ca_key" ]; then
    seal_plaintext_key "$legacy_ca_key"
  else
    if command -v shred >/dev/null 2>&1; then
      shred -u "$legacy_ca_key" 2>/dev/null || rm -f "$legacy_ca_key"
    else
      rm -f "$legacy_ca_key"
    fi
  fi
fi

if [ ! -s "$encrypted_ca_key" ]; then
  if [ -s "$ca_crt" ]; then
    echo "nebula-ca-unseal: refusing to continue with cert present but missing encrypted CA key" >&2
    exit 1
  fi

  tmpdir="$(mktemp -d)"
  nebula-cert ca \
    -name s-router-test-lab \
    -out-crt "$tmpdir/ca.crt" \
    -out-key "$tmpdir/ca.key"
  install -m 0600 "$tmpdir/ca.crt" "$ca_crt"
  seal_plaintext_key "$tmpdir/ca.key"
fi

rm -f "$unsealed_ca_key"
openssl enc -d -aes-256-cbc -pbkdf2 \
  -in "$encrypted_ca_key" \
  -out "$unsealed_ca_key" \
  -pass "file:$passphrase_file"
chmod 0600 "$unsealed_ca_key"
      '';
