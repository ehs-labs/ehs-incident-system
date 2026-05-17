# WebSocket protocol

The notifier exposes a single WebSocket endpoint that the SPA connects to for
**in-app notifications**.

## Connection

```
wss://<notifier-host>/ws?token=<jwt>
Sec-WebSocket-Protocol: ehs.v1
```

The JWT is the same access token used for REST API calls. The notifier verifies
it with the same `JWT_SECRET` (mounted from K8s Secret in prod, env var in dev).

## Message types

All frames are JSON `{ "type": ..., ... }`.

### Server → Client

```ts
type ServerMessage =
  | { type: "connected"; server_time: string }
  | { type: "pong" }
  | { type: "notification"; payload: Notification }
  | { type: "error"; code: string; message: string };

interface Notification {
  id: string;          // ULID
  kind: string;        // event_type, e.g. "IncidentAssigned"
  title: string;
  body: string;
  link: string;        // relative URL — e.g. "/incidents/01HXY..."
  created_at: string;  // ISO-8601 UTC
  read_at: string | null;
}
```

After `connected`, the server replays the user's **last 20 unread in-app
notifications** so a re-connecting client sees them without polling.

### Client → Server

```ts
type ClientMessage = { type: "ping" };
```

The client pings every 30 s. The server responds with `{ "type": "pong" }`. The
ping serves both as keepalive and as a connection-health check — if no pong
arrives, the client triggers reconnect.

## Reconnect strategy

Exponential backoff with jitter, 1s start → 30s cap. Implemented in
[`frontend/src/composables/useNotifications.ts`](../../frontend/src/composables/useNotifications.ts).

```
attempt 1 → wait 1s + jitter
attempt 2 → wait 2s + jitter
attempt 3 → wait 4s + jitter
...
attempt N → wait min(2^(N-1), 30) + jitter
```

After a successful reconnect, the server's `connected` message replays the last
20 unread, so the client never has to ask "did I miss anything?"

## Multi-tab

Each tab opens its own WS. The notifier's `WsServer` keeps a `user_id → Set<connection>` map. When the in-app channel dispatches a notification, all tabs receive it (each one updates its own Pinia store).

## Why query-string token

We use `?token=` rather than a custom `Sec-WebSocket-Protocol` header for JWT because:

1. Browsers don't let you set custom headers on `new WebSocket()` calls
2. The connection is over `wss://` (TLS), so the URL is encrypted in transit
3. The token is short-lived (15m) so even if it leaks in proxy logs, the window is small

The notifier never logs `?token=...` URLs — they're scrubbed before logging.
