# Key rotation (field cipher)

Last rehearsed: 2026-05-18. Run `bash scripts/key-rotation-drill.sh` to re-verify.

Full sequence diagram in [`docs/flows/key-rotation.md`](../flows/key-rotation.md).

## TL;DR

```bash
# 1. Generate v2
openssl rand -base64 32

# 2. Add the v2 secret alongside v1 (dual-mount window)
kubectl -n ehs patch secret ehs-secrets --type='json' -p='[
  {"op": "add", "path": "/data/FIELD_CIPHER_KEY_V2", "value": "<base64>"}
]'

# 3. Update deployments to mount both keys (active=v1)
# ...

# 4. Flip producer to active=v2
# ...

# 5. Run rewrite job to replay users.v1 with v2 encryption
# ...

# 6. Retire v1
```

## Why versioned wire format

`v1:nonce:ct:tag` — the leading `v1` lets the consumer know which key to use.
Without it, every rotation would need a coordinated stop. With it, both keys
can coexist for as long as the rotation takes.

See ADR-0004 for the full reasoning.

## Rehearsal drill

Run a one-shot drill any time you want to verify the gem's rotation behaviour
before touching production keys:

```bash
bash scripts/key-rotation-drill.sh
```

The script:
1. Generates fresh random v1 and v2 keys.
2. Encrypts plaintext under v1 (Phase 1 baseline).
3. Flips `active_version` to v2, encrypts new plaintext, confirms the dual-keyring
   decrypts both the old v1 and new v2 ciphertexts (Phases 2 and 3).
4. Retires v1 from the keyring and asserts that the old v1 ciphertext now raises
   `Ehs::Envelope::UnknownKeyVersion` (Phase 4).

Exits non-zero and prints `FAIL` if any assertion does not hold. The full
procedure is captured in `docs/flows/key-rotation.md`.
