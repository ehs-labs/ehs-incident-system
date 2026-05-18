#!/usr/bin/env bash
# key-rotation-drill.sh — rehearses the four-phase field-cipher key rotation
# in an ephemeral Ruby process so the running stack's keys are never touched.
#
# See docs/flows/key-rotation.md for the full sequence diagram.
# See docs/operations/key-rotation.md for the operations runbook.
#
# Usage:
#   bash scripts/key-rotation-drill.sh
#
# The script is idempotent (generates fresh random keys every run).
set -euo pipefail

RUBY="${RUBY:-/opt/homebrew/opt/ruby@3/bin/ruby}"
ENVELOPE_LIB="$(cd "$(dirname "$0")/../shared/envelope/lib" && pwd)"

require_ruby() {
  if ! command -v "$RUBY" &>/dev/null; then
    echo "ERROR: Ruby not found at $RUBY. Set RUBY= env var to override." >&2
    exit 1
  fi
}

require_ruby

echo "=== Key-rotation drill ==="
echo "Ruby: $($RUBY --version)"
echo "Envelope lib: $ENVELOPE_LIB"
echo ""

# Generate fresh v1 and v2 keys (32 random bytes, base64-encoded)
V1_KEY=$(openssl rand -base64 32)
V2_KEY=$(openssl rand -base64 32)

echo "Generated v1 key (first 8 chars): ${V1_KEY:0:8}..."
echo "Generated v2 key (first 8 chars): ${V2_KEY:0:8}..."
echo ""

"$RUBY" - "$ENVELOPE_LIB" "$V1_KEY" "$V2_KEY" <<'RUBY_SCRIPT'
$LOAD_PATH.unshift(ARGV[0])
require "ehs/envelope"

v1_key = ARGV[1]
v2_key = ARGV[2]

puts "--- Phase 1: encrypt with v1 only (pre-rotation baseline) ---"
cipher_v1_only = Ehs::Envelope.new(keys: { "v1" => v1_key }, active_version: "v1")
ct_v1 = cipher_v1_only.encrypt("rotation-test-pii")
puts "  v1 ciphertext prefix : #{ct_v1[0..40]}..."
puts "  round-trip decrypt   : #{cipher_v1_only.decrypt(ct_v1)}"
abort "FAIL: v1 round-trip failed" unless cipher_v1_only.decrypt(ct_v1) == "rotation-test-pii"
puts "  PASS"
puts ""

puts "--- Phase 2: dual-keyring, flip producer to v2 ---"
cipher_dual = Ehs::Envelope.new(keys: { "v1" => v1_key, "v2" => v2_key }, active_version: "v2")
ct_v2 = cipher_dual.encrypt("new-pii-under-v2")
puts "  v2 ciphertext prefix : #{ct_v2[0..40]}..."
puts "  decrypt v2 ciphertext: #{cipher_dual.decrypt(ct_v2)}"
abort "FAIL: v2 decrypt failed" unless cipher_dual.decrypt(ct_v2) == "new-pii-under-v2"
puts "  PASS"
puts ""

puts "--- Phase 3: dual-keyring decrypts legacy v1 ciphertext ---"
pt_from_old = cipher_dual.decrypt(ct_v1)
puts "  decrypted old v1 ct  : #{pt_from_old}"
abort "FAIL: dual-keyring could not decrypt v1 ciphertext" unless pt_from_old == "rotation-test-pii"
puts "  PASS"
puts ""

puts "--- Phase 4: retire v1 - v1 ciphertext must now FAIL ---"
cipher_v2_only = Ehs::Envelope.new(keys: { "v2" => v2_key }, active_version: "v2")
begin
  cipher_v2_only.decrypt(ct_v1)
  abort "FAIL: expected UnknownKeyVersion but decrypt succeeded"
rescue Ehs::Envelope::UnknownKeyVersion => e
  puts "  Got expected error: Ehs::Envelope::UnknownKeyVersion (#{e.message})"
  puts "  PASS"
end
puts ""

puts "=== All phases passed ==="
RUBY_SCRIPT

echo ""
echo "Drill completed successfully on $(date -u '+%Y-%m-%d')."
