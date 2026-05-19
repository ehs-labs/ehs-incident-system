<script setup lang="ts">
import {
  NLayout,
  NLayoutSider,
  NLayoutHeader,
  NLayoutContent,
  NMenu,
  NBadge,
  NButton,
  NDropdown,
  NSpace,
  type MenuOption
} from "naive-ui";
import { computed, h } from "vue";
import { RouterLink, useRouter, useRoute } from "vue-router";
// (NIcon and friends not used yet; kept lean.)
import { useAuthStore } from "@/stores/auth";
import {
  useNotificationStore,
  useNotifications
} from "@/composables/useNotifications";

useNotifications(); // establishes the WS connection for the duration of the shell

const auth = useAuthStore();
const router = useRouter();
const route = useRoute();
const notifications = useNotificationStore();

const sideMenu = computed<MenuOption[]>(() => {
  const base: { label: string; key: string }[] = [
    { label: "Dashboard", key: "/dashboard" },
    { label: "Incidents", key: "/incidents" },
    { label: "My Actions", key: "/actions" },
    { label: "Inbox", key: "/inbox" }
  ];
  if (auth.user?.role === "admin") {
    base.push(
      { label: "Admin · Users", key: "/admin/users" },
      { label: "Admin · Sites", key: "/admin/sites" },
      { label: "Admin · Settings", key: "/admin/settings" }
    );
  }
  return base.map((b) => ({
    key: b.key,
    label: () =>
      h(
        RouterLink,
        {
          to: b.key,
          style: "text-decoration: none; color: inherit; display: block"
        },
        () => {
          if (b.key === "/inbox" && notifications.unreadCount > 0) {
            return h("span", { style: "display:flex; align-items:center; gap:8px" }, [
              b.label,
              h(NBadge, { value: notifications.unreadCount, max: 99 })
            ]);
          }
          return b.label;
        }
      )
  }));
});

const activeKey = computed(() => {
  const m = sideMenu.value
    .map((o) => o.key as string)
    .filter((k) => route.path.startsWith(k))
    .sort((a, b) => b.length - a.length);
  return m[0] ?? "/dashboard";
});

const userMenu = computed(() => [
  { key: "profile", label: `${auth.user?.email} (${auth.user?.role})` },
  { type: "divider", key: "d1" },
  { key: "logout", label: "Sign out" }
]);

async function onUserSelect(key: string) {
  if (key === "logout") {
    await auth.logout();
    router.push("/login");
  }
}
</script>

<template>
  <n-layout
    has-sider
    style="height: 100vh"
  >
    <n-layout-sider
      bordered
      width="220"
      collapse-mode="width"
      :collapsed-width="0"
      show-trigger="bar"
      content-style="padding: 16px"
    >
      <h2 style="margin: 0 0 16px 0; font-size: 18px">
        EHS Incidents
      </h2>
      <n-menu
        :options="sideMenu"
        :value="activeKey"
      />
    </n-layout-sider>

    <n-layout>
      <n-layout-header
        bordered
        style="display:flex; align-items:center; justify-content:space-between; padding: 8px 24px; gap: 16px"
      >
        <n-space align="center">
          <strong style="margin-right: 8px">{{ auth.organization?.name ?? "EHS" }}</strong>
        </n-space>

        <n-space
          align="center"
          :size="16"
        >
          <RouterLink
            to="/inbox"
            style="text-decoration: none"
          >
            <n-badge
              :value="notifications.unreadCount"
              :show="notifications.unreadCount > 0"
              :max="99"
            >
              <n-button quaternary>
                Inbox
              </n-button>
            </n-badge>
          </RouterLink>
          <n-dropdown
            trigger="click"
            :options="userMenu"
            @select="onUserSelect"
          >
            <n-button quaternary>
              {{ auth.user?.email }} · {{ auth.user?.role }}
            </n-button>
          </n-dropdown>
        </n-space>
      </n-layout-header>

      <n-layout-content content-style="padding: 24px; min-height: calc(100vh - 56px)">
        <router-view />
      </n-layout-content>
    </n-layout>
  </n-layout>
</template>

<style scoped>
@media (max-width: 600px) {
  :deep(.n-layout-header) {
    padding: 8px 12px !important;
    flex-wrap: wrap;
  }
}
</style>
