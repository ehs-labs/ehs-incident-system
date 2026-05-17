# ehs-envelope

A small local-path Ruby gem providing **AES-256-GCM field-level encryption** for
PII shared between the `core-api` (Rails) and `notifier` (Sinatra) services via
the `users.v1` Kafka topic.

## Why this exists

Domain events (`incidents.v1`, etc.) carry only `recipient_user_ids` — never PII.
The `users.v1` topic is the exception: it carries names, emails, and Telegram
chat IDs so the notifier can resolve recipients without calling back to
`core-api`.

To keep PII out of plaintext on the broker (defense-in-depth against compromised
disks, ACL gaps, or future consumers like analytics), those fields are
encrypted at the field level using this library before publishing, and decrypted
on consume.

## Wire format

```
v<key_version>:<nonce_b64>:<ciphertext_b64>:<tag_b64>
```

The version prefix makes key rotation safe — see [`docs/operations/key-rotation.md`](../../docs/operations/key-rotation.md).

## Usage

```ruby
require "ehs/envelope"

cipher = Ehs::Envelope.new(
  keys:           { "v1" => ENV.fetch("FIELD_CIPHER_KEY") },
  active_version: "v1"
)

encoded = cipher.encrypt("alice@example.com")
# => "v1:abc...:xyz...:tag..."

decoded = cipher.decrypt(encoded)
# => "alice@example.com"
```

## Key rotation

```ruby
# Phase 1 — dual-decrypt window: deploy notifier with both keys mounted,
# core-api still encrypts with v1.
Ehs::Envelope.new(keys: { "v1" => k1, "v2" => k2 }, active_version: "v1")

# Phase 2 — flip producer to v2, drain old messages.
Ehs::Envelope.new(keys: { "v1" => k1, "v2" => k2 }, active_version: "v2")

# Phase 3 — run one-shot replay job that re-encrypts compacted topic under v2,
# then remove v1 key from secrets.
Ehs::Envelope.new(keys: { "v2" => k2 }, active_version: "v2")
```

## Tests

```bash
bundle install
bundle exec rspec
```

## Key generation

```bash
ruby -rbase64 -rsecurerandom -e 'puts Base64.strict_encode64(SecureRandom.bytes(32))'
```

Store the resulting string in `FIELD_CIPHER_KEY` (env var in dev/compose, K8s
Secret mounted as a file in production).
