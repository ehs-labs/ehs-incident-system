# Key rotation (field cipher)

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
