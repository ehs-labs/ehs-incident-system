# Deployment topology

```mermaid
%%{init: {'flowchart': {'htmlLabels': true}, 'themeVariables': {'fontSize': '16px'}}}%%
flowchart TB
    user((User))

    subgraph cluster["Kubernetes cluster"]
        subgraph ns["namespace: ehs"]
            direction TB
            ing["<b>Ingress</b><br/>nginx-ingress<br/>app.ehs.test"]

            subgraph apps["Apps"]
                direction LR
                noD["Deployment: notifier<br/>Falcon HTTP/WS"]
                feD["Deployment: frontend<br/>nginx + dist/"]
                caD["Deployment: core-api<br/>HPA 2-6"]
                sqD["Deployment: sidekiq"]
                nkD["Deployment: notifier-karafka<br/>Karafka consumer"]
            end

            subgraph infra["Infrastructure"]
                direction LR
                mn["StatefulSet: minio<br/>PVC 5Gi"]
                pg["StatefulSet: postgres<br/>PVC 5Gi"]
                rd["Deployment: redis"]
                ka["Deployment: karapace"]
                kf["StatefulSet: kafka KRaft<br/>PVC 5Gi"]
                mc["Deployment: mailcatcher"]
            end

            subgraph jobs["Migration jobs (run before apps)"]
                direction LR
                jA["Job: db-migrate-core-api"]
                jN["Job: db-migrate-notifier"]
            end

            subgraph clusterCfg["Cluster-wide config"]
                direction LR
                cm["ConfigMap: ehs-config"]
                sc["Secret: ehs-secrets"]
                np["NetworkPolicies"]
            end
        end
    end

    user --> ing
    ing -- "/ws"  --> noD
    ing -- "/api" --> caD
    ing -- "/"    --> feD

    feD --> caD

    caD --> mn
    caD --> pg
    caD --> rd
    caD --> ka

    sqD --> pg
    sqD --> rd
    sqD --> kf

    noD --> pg

    nkD --> ka
    nkD --> kf

    jA -.before.-> caD
    jN -.before.-> nkD

    clusterCfg -. "injected into" .-> apps

    style clusterCfg fill:none,stroke:#999,stroke-dasharray:3 3,color:#666
    style jobs       fill:none,stroke:#999,stroke-dasharray:3 3,color:#666
```

## Apply order

The release script (or ArgoCD sync waves) applies in this order:

1. `Namespace`, `ConfigMap`, `Secret`
2. `StatefulSet`s and `Deployment`s for **infrastructure** (Postgres, Redis, Kafka, Karapace, MinIO, MailCatcher) — they have no dependency on the apps
3. `Job/db-migrate-core-api` and `Job/db-migrate-notifier` — block on `condition=Complete`
4. App `Deployment`s — only proceed after migrations are done
5. `Ingress` — exposes once apps are ready
6. `NetworkPolicy` — applied last (or anytime — it's purely additive)

If step 3 fails, step 4 is never executed → old pods keep serving traffic with the previous schema. Even if a new pod somehow boots against an unmigrated DB, the **boot-time tripwire** kills it on startup (see [`docs/operations/migrations.md`](../operations/migrations.md)).

## Overlay differences

| | `local/` overlay | `cloud/` overlay |
|---|---|---|
| Replicas | 1 of everything | 2 of `core-api`, `notifier`, `frontend`; HPA up to 6 |
| Storage class | default (Docker Desktop / kind hostPath) | encrypted PVC class |
| Ingress | NodePort or `/etc/hosts` to `app.ehs.test` | LoadBalancer + cert-manager Let's Encrypt |
| Secrets | committed dev values | External Secrets Operator or out-of-band `kubectl create` |
| Kafka security | PLAINTEXT (single-node) | TLS + SASL/SCRAM + ACLs |
