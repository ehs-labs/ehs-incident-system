# End-to-end verification checklist

A permanent step-by-step demo + smoke test. Use it as:
- An onboarding walkthrough for new contributors
- A pre-release smoke test against staging
- A reminder script when returning to the repo after time away

## 1. Bring up the stack

```bash
git clone https://github.com/ehs-labs/ehs-incident-system
cd ehs-incident-system
cp .env.example .env
./scripts/bootstrap.sh
```

✅ Expected: the script prints `✓ EHS Incident System is up.` and lists service URLs.

## 2. Functional smoke

Open `http://localhost:5173`.

- [ ] Sign up as a new user → land on dashboard for a brand-new Org
- [ ] OR log in as `admin@acme.demo` / `password` (from demo seed)
- [ ] Submit a new incident with one photo attachment
- [ ] Open the bell-icon dropdown — see an "Incident submitted" notification appear *immediately* (proves WebSocket works)
- [ ] Open MailCatcher at `http://localhost:1080` — see the corresponding email
- [ ] Log out, log in as `investigator@acme.demo` / `password` in a second browser/profile
- [ ] See the same incident in the dashboard
- [ ] Triage it (assign severity + yourself)
- [ ] Add a corrective action with due date in 7 days
- [ ] Switch back to the worker account — see the assigned action in the inbox

## 3. Event-flow verification

- [ ] Open Kafka UI at `http://localhost:8080`
- [ ] Cluster: `local` → Topics → `incidents.v1` → Messages
- [ ] Confirm you see the `IncidentSubmitted` and `IncidentAssigned` events in Avro
- [ ] Switch to `corrective_actions.v1` — confirm `CorrectiveActionAssigned`

## 4. Operational sanity

- [ ] Sidekiq dashboard at `http://localhost:3000/sidekiq` — `OutboxShipperJob` shows recent successes; queues are empty/draining
- [ ] Karapace at `http://localhost:8081/subjects` — returns the list of registered schemas
- [ ] MinIO console at `http://localhost:9001` (`minioadmin` / `minioadmin`) — the `ehs-attachments` bucket contains the uploaded photo

## 5. Backend tests

```bash
cd core-api && bundle exec rspec
cd ../notifier && bundle exec rspec
cd ../shared/envelope && bundle exec rspec
```

- [ ] All suites green
- [ ] Coverage report at `core-api/coverage/index.html` is ≥ 80% on controllers/jobs, ≥ 90% on models/policies/services

## 6. Frontend tests

```bash
cd frontend
pnpm install
pnpm run typecheck
pnpm run lint
pnpm run test:unit
```

- [ ] Vitest green
- [ ] `vue-tsc` reports no errors
- [ ] ESLint green

## 7. End-to-end (Playwright)

```bash
cd frontend
pnpm exec playwright install --with-deps chromium
pnpm run test:e2e
```

- [ ] All gold-path scenarios green:
  - [ ] Worker → Investigator round-trip (WS + email)
  - [ ] Full state-machine round-trip (submit → triage → assign → complete → close)
  - [ ] SLA breach detection
  - [ ] Authorization (worker cannot access another worker's incident)
  - [ ] Telegram opt-in (mocked bot)

## 8. K8s deployment (local cluster)

```bash
./scripts/k8s-up.sh
```

- [ ] All pods `Running` in namespace `ehs`
- [ ] `kubectl -n ehs get jobs` shows `db-migrate-core-api` and `db-migrate-notifier` both `Complete`
- [ ] Re-run the functional smoke (step 2) against the K8s deploy via the ingress

## 9. CI green

- [ ] Push to a feature branch → GitHub Actions runs and passes:
  - lint, security, test-core-api, test-notifier, test-frontend, contracts, e2e

## 10. Security & PII

- [ ] In Kafka UI, view `users.v1` — confirm `email_enc`, `name_enc`, `telegram_chat_id_enc` are ciphertext (not plaintext)
- [ ] Confirm `incidents.v1` payloads contain `recipient_user_ids` but no email/phone/chat-id
- [ ] In K8s, swap the `FIELD_CIPHER_KEY` Secret to a wrong value, restart notifier — consumer should refuse to start (decryption error)

## 11. Documentation review

- [ ] Open `docs/` in the GitHub web UI
- [ ] Every Mermaid diagram renders
- [ ] Every ADR has `Status / Context / Decision / Consequences` sections filled in
- [ ] README's "Try it in 5 minutes" steps still match `scripts/bootstrap.sh`

## 12. Git / GitHub readiness

- [ ] `git status` clean after `bootstrap.sh`
- [ ] `.env` is NOT tracked (`git ls-files | grep '^\.env$'` returns nothing)
- [ ] Dependabot config syntactically valid (`gh api repos/:owner/:repo/dependabot/alerts` works)
- [ ] PR template renders when you start a new PR; issue templates render under "New issue"
