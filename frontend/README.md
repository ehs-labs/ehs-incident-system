# frontend

Vue 3 + TypeScript + Vite SPA. Talks to `core-api` over REST/JWT and to `notifier` over WebSocket.

## Quick reference

| Command | Purpose |
|---|---|
| `pnpm install` | Install deps |
| `pnpm dev` | Vite dev server on :5173 |
| `pnpm build` | Type-check + production build to `dist/` |
| `pnpm preview` | Serve the built `dist/` locally |
| `pnpm test:unit` | Vitest |
| `pnpm test:e2e` | Playwright (needs full compose stack up) |
| `pnpm lint` | ESLint (Vue + TS) |
| `pnpm typecheck` | `vue-tsc --noEmit` |
| `pnpm gen:api` | Regenerate types from `../core-api/openapi.yaml` |

## Layout

```
frontend/
├── src/
│   ├── api/              # Axios + generated OpenAPI types
│   ├── components/       # Reusable bits (IncidentCard, SeverityBadge, …)
│   ├── composables/      # useAuth, useNotifications (owns the WS), …
│   ├── layouts/          # AppShell with sidebar + topbar
│   ├── router/           # Routes + guards
│   ├── stores/           # Pinia
│   ├── types/            # Hand-written TS types
│   ├── utils/
│   └── views/            # Page components
├── tests/
│   ├── unit/             # Vitest
│   └── e2e/              # Playwright
├── Dockerfile            # dev (vite) and final (nginx) stages
├── nginx.conf
├── vite.config.ts
├── tsconfig.json
└── playwright.config.ts
```

## How the WebSocket flow works

`useNotifications()` (in `src/composables/`) opens a `wss://notifier.../ws?token=...`
connection on AppShell mount, joins the per-user channel server-side, receives
`{ type: "notification", payload }` frames, and pushes them into a Pinia store.
The bell badge in the topbar reads `unreadCount` from that store.

Reconnection: exponential backoff with jitter (1s → 30s cap).

## OpenAPI-driven types

`core-api` emits `openapi.yaml` from rswag request specs. `pnpm gen:api` runs
`openapi-typescript` to generate `src/api/generated/schema.ts`. Hand-written types
in `src/types/` augment the generated ones.
