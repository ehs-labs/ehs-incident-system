import { ref, onUnmounted } from "vue";
import { defineStore } from "pinia";
import { useAuthStore } from "@/stores/auth";

export interface Notification {
  // delivery_log.id is an integer on the wire; normalize via String() at upsert.
  id: string;
  event_type: string;
  title: string;
  body: string;
  link: string;
  created_at: string;
  read_at: string | null;
}

// ---------------------------------------------------------------------------
// Pinia store — holds the live notification list
// ---------------------------------------------------------------------------
export const useNotificationStore = defineStore("notifications", {
  state: () => ({
    items: [] as Notification[],
    connected: false
  }),
  getters: {
    unreadCount: (s) => s.items.filter((n) => !n.read_at).length
  },
  actions: {
    upsert(n: Notification) {
      // Backend sends delivery_log.id as an integer; coerce to string so the
      // replay-on-connect frame and the live-push frame de-dup correctly.
      const normalized: Notification = { ...n, id: String(n.id) };
      const idx = this.items.findIndex((x) => x.id === normalized.id);
      if (idx >= 0) this.items[idx] = normalized;
      else this.items.unshift(normalized);
    },
    markRead(id: string) {
      const n = this.items.find((x) => x.id === id);
      if (n) n.read_at = new Date().toISOString();
    },
    setConnected(value: boolean) {
      this.connected = value;
    },
    // Pinia stores survive across component lifecycles, so a prior user's
    // notifications would otherwise leak into the next user's inbox until a
    // full page reload. Auth#logout calls this to drop the in-memory list.
    clear() {
      this.items = [];
      this.connected = false;
    }
  }
});

// ---------------------------------------------------------------------------
// Composable — owns the WebSocket lifecycle. Exponential backoff with jitter.
// ---------------------------------------------------------------------------
export function useNotifications() {
  const store = useNotificationStore();
  const auth = useAuthStore();
  const ws = ref<WebSocket | null>(null);
  let backoffMs = 1000;
  let pingTimer: number | null = null;
  let stopped = false;

  function connect() {
    if (stopped || !auth.accessToken) return;

    const wsUrl = import.meta.env.VITE_WS_URL ?? "ws://localhost:4000/ws";
    const url = `${wsUrl}?token=${encodeURIComponent(auth.accessToken)}`;
    ws.value = new WebSocket(url, ["ehs.v1"]);

    ws.value.onopen = () => {
      store.setConnected(true);
      backoffMs = 1000;
      pingTimer = window.setInterval(() => {
        ws.value?.send(JSON.stringify({ type: "ping" }));
      }, 30_000);
    };

    ws.value.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "notification") store.upsert(data.payload);
      } catch {
        /* ignore malformed */
      }
    };

    ws.value.onclose = () => {
      store.setConnected(false);
      if (pingTimer) window.clearInterval(pingTimer);
      if (stopped) return;
      const jitter = Math.random() * 500;
      window.setTimeout(connect, Math.min(backoffMs + jitter, 30_000));
      backoffMs = Math.min(backoffMs * 2, 30_000);
    };
  }

  connect();

  onUnmounted(() => {
    stopped = true;
    ws.value?.close();
    if (pingTimer) window.clearInterval(pingTimer);
    // The shell only unmounts on logout (the auth-protected layout is left
    // behind for /login). Drop the in-memory list so the next user's WS
    // replay starts from a clean inbox.
    store.clear();
  });

  return { store };
}
