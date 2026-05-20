# C4 Level 3 — Vue SPA internals

```mermaid
flowchart LR
    user[/User<br/>browser/]

    subgraph spa["frontend (Vue 3 + Vite + Pinia + Naive UI)"]
        direction TB

        subgraph entry["Entry & shell"]
            main[main.ts<br/><i>Pinia + Router + Naive UI</i>]
            app[App.vue]
            shell[AppShell.vue<br/><i>authenticated layout</i>]
        end

        subgraph router["Vue Router"]
            public[Public routes<br/><i>/login /signup /password/reset</i>]
            authed[Authenticated routes<br/><i>Dashboard / Incidents / Actions /<br/>Inbox / Profile</i>]
            adminR[Admin routes<br/><i>Users / Sites / Settings</i>]
            guard[beforeEach guard<br/><i>tryRefresh + role gate</i>]
        end

        subgraph views["Views"]
            pubV[Login / Signup /<br/>PasswordReset / NotFound]
            authedV[Dashboard / Incidents /<br/>IncidentNew / IncidentDetail /<br/>Actions / Inbox]
            adminV[admin/UserList / UserInvite /<br/>UserEdit / SiteList / Settings / Profile]
        end

        subgraph stores["Pinia stores"]
            authStore[auth<br/><i>jwt + user + sites + org<br/>tryRefresh</i>]
            notifStore[notification<br/><i>live list + connection state</i>]
        end

        subgraph composables["Composables"]
            useNotif[useNotifications<br/><i>WS lifecycle + backoff</i>]
        end

        subgraph apiLayer["HTTP client"]
            axios[axios instance<br/><i>Bearer injector +<br/>401 refresh interceptor +<br/>RFC 7807 parser +<br/>Link-header pagination</i>]
            modules[incidents / actions /<br/>dashboard / admin]
            schema[schema.ts<br/><i>OpenAPI types</i>]
        end

        ws[WebSocket client<br/><i>?token + ehs.v1 subprotocol</i>]

        subgraph storage["Browser storage"]
            ls[(localStorage<br/>ehs.jwt / ehs.user /<br/>ehs.org / ehs.sites)]
            cookie[(httpOnly refresh cookie)]
        end
    end

    coreApi[/core-api<br/>REST + JWT/]
    notifier[/notifier<br/>WebSocket/]

    user --> main --> app --> shell
    shell --> router
    router --> guard --> authStore
    public --> pubV
    authed --> authedV
    adminR --> adminV
    authedV & adminV --> authStore
    authedV & adminV --> notifStore
    authedV & adminV --> modules
    useNotif --> notifStore
    useNotif --> ws
    useNotif --> authStore
    modules --> axios
    modules --> schema
    axios --> authStore
    authStore --> ls
    authStore -.->|sends cookie| cookie

    axios -->|REST + Bearer| coreApi
    cookie -.->|refresh| coreApi
    ws -->|WSS| notifier
```

## Why this shape

- **Pinia stores own session and live state** — `auth` holds the access token, current user, org, and sites; `notification` holds the live in-app list. Everything else (views, composables, axios interceptor) reads from these stores rather than threading props or duplicating state.
- **One axios instance, two interceptors** — request injects `Authorization: Bearer <jwt>`, response handles 401 by routing through `auth.tryRefresh()`. Centralising this means no view ever sees a 401.
- **OpenAPI-generated types** — [frontend/src/api/schema.ts](../../frontend/src/api/schema.ts) is generated from `core-api/openapi.yaml` so the request/response shapes are type-checked against the backend contract at build time.
- **One composable owns the WebSocket** — `useNotifications` is the only thing that opens, pings, reconnects, and closes the WS connection. Views just read from the `notification` store.
- **Naive UI + flat components** — only three custom leaf components ([DurationInput.vue](../../frontend/src/components/DurationInput.vue), [SeverityBar.vue](../../frontend/src/components/SeverityBar.vue), [TrendChart.vue](../../frontend/src/components/TrendChart.vue)). Everything else composes Naive UI primitives directly in views — no premature component hierarchy.
- **Two storage layers** — access token in `localStorage` (so the axios interceptor can read it synchronously); refresh token in an httpOnly cookie (so JS can't touch it). The refresh call sends the cookie with `withCredentials: true` and gets a fresh access token back in the response.

## Auth refresh

```mermaid
sequenceDiagram
    autonumber
    participant View
    participant Axios as axios
    participant Auth as auth store
    participant Core as core-api

    View->>Axios: GET /incidents
    Axios->>Core: + Bearer <expired jwt>
    Core-->>Axios: 401
    Axios->>Auth: tryRefresh()
    Auth->>Core: POST /auth/refresh<br/>(httpOnly cookie)
    alt refresh ok
        Core-->>Auth: new access token
        Auth-->>Axios: token
        Axios->>Core: retry GET /incidents + new Bearer
        Core-->>View: 200
    else refresh fails
        Auth->>Auth: clear() session
        Auth-->>View: redirect /login?next=<path>
    end
```

Concurrent 401s are coalesced — only one `tryRefresh()` is in flight at a time; queued requests retry once it resolves. Implementation in [frontend/src/api/axios.ts](../../frontend/src/api/axios.ts); store actions in [frontend/src/stores/auth.ts](../../frontend/src/stores/auth.ts). End-to-end version of this flow lives in [docs/flows/auth-and-jwt-refresh.md](../flows/auth-and-jwt-refresh.md).

## WebSocket lifecycle

```mermaid
sequenceDiagram
    autonumber
    participant Boot as app boot
    participant Auth as auth store
    participant UN as useNotifications
    participant Notif as notifier (WS)

    Boot->>Auth: hydrate from localStorage
    Auth->>UN: token present → open()
    UN->>Notif: connect ?token=<jwt><br/>subprotocol ehs.v1
    Notif-->>UN: open
    loop every 30s
        UN->>Notif: ping
    end
    Notif-->>UN: notification frame
    UN->>UN: store.upsert(...)
    Note over UN,Notif: on close
    UN->>UN: backoff (exponential)
    alt still authenticated
        UN->>Notif: reconnect
    else logged out
        UN->>UN: stop
    end
```

URL is `VITE_WS_URL` if set, otherwise derived from `window.location` (so prod doesn't need a separate env var). Logout calls `store.clear()` on the notification store so the next login doesn't leak the previous user's notifications. Code: [frontend/src/composables/useNotifications.ts](../../frontend/src/composables/useNotifications.ts).

## Route guards

[frontend/src/router/index.ts](../../frontend/src/router/index.ts) registers a single `beforeEach` that:

1. Calls `auth.tryRefresh()` on any protected route — so a tab left open across token expiry refreshes transparently instead of bouncing to login.
2. Redirects to `/login?next=<path>` if no session can be restored.
3. Checks role from the auth store for `/admin/*` routes; non-admins are redirected to `/`.

## See also

- [03-c4-component-core-api.md](03-c4-component-core-api.md) — the REST surface this client talks to
- [03-c4-component-notifier.md](03-c4-component-notifier.md) — the WS server on the other end
- [02-c4-container.md](02-c4-container.md) — how this fits into the broader topology
