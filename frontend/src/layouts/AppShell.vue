<script setup lang="ts">
import { NLayout, NLayoutSider, NLayoutHeader, NMenu, NBadge, NIcon } from "naive-ui";
import { computed, h } from "vue";
import { RouterLink, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { useNotificationStore, useNotifications } from "@/composables/useNotifications";

useNotifications(); // establishes the WS connection for the duration of the shell

const auth = useAuthStore();
const router = useRouter();
const notifications = useNotificationStore();

const menuOptions = computed(() => {
  const base = [
    { label: "Dashboard",  key: "/dashboard",        href: "/dashboard" },
    { label: "Incidents",  key: "/incidents",        href: "/incidents" },
    { label: "Actions",    key: "/actions",          href: "/actions" },
    { label: "Inbox",      key: "/inbox",            href: "/inbox" }
  ];
  if (auth.user?.role === "admin") {
    base.push(
      { label: "Users",    key: "/admin/users",      href: "/admin/users" },
      { label: "Sites",    key: "/admin/sites",      href: "/admin/sites" },
      { label: "Settings", key: "/admin/settings",   href: "/admin/settings" }
    );
  }
  return base.map((b) => ({
    label: () => h(RouterLink, { to: b.href }, () => b.label),
    key: b.key
  }));
});

async function signOut() {
  await auth.logout();
  router.push("/login");
}
</script>

<template>
  <n-layout has-sider style="height: 100vh">
    <n-layout-sider
      bordered
      width="220"
      content-style="padding: 16px"
    >
      <h2 style="margin: 0 0 16px 0">EHS</h2>
      <n-menu :options="menuOptions" />
    </n-layout-sider>

    <n-layout>
      <n-layout-header bordered style="display: flex; align-items: center; padding: 12px 24px; justify-content: space-between">
        <span>{{ auth.user?.name }} · {{ auth.user?.role }}</span>
        <div style="display: flex; gap: 16px; align-items: center">
          <RouterLink to="/inbox">
            <n-badge :value="notifications.unreadCount" :show="notifications.unreadCount > 0">
              <span>🔔</span>
            </n-badge>
          </RouterLink>
          <button @click="signOut">Sign out</button>
        </div>
      </n-layout-header>

      <n-layout content-style="padding: 24px">
        <router-view />
      </n-layout>
    </n-layout>
  </n-layout>
</template>
