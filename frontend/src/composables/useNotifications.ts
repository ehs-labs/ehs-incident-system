import { ref, onUnmounted } from "vue";
import { defineStore } from "pinia";
import { useAuthStore } from "@/stores/auth";

interface Notification {
  id: string;
  kind: string;
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
      const idx = this.items.findIndex((x) => x.id === n.id);
      if (idx >= 0) this.items[idx] = n;
      else this.items.unshift(n);
    },
    markRead(id: string) {
      const n = this.items.find((x) => x.id === id);
      if (n) n.read_at = new Date().toISOString();
    },
    setConnected(value: boolean) {
      this.connected = value;
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
  });

  return { store };
}
