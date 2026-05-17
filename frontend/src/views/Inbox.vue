<script setup lang="ts">
import {
  NList,
  NListItem,
  NThing,
  NEmpty,
  NSpace,
  NBadge,
  NTag,
  NCard
} from "naive-ui";
import { useRouter } from "vue-router";
import { useNotificationStore } from "@/composables/useNotifications";
import { fmtRelative } from "@/utils/format";

const router = useRouter();
const notifications = useNotificationStore();

function openItem(id: string, link: string) {
  notifications.markRead(id);
  if (link) router.push(link);
}
</script>

<template>
  <n-space
    vertical
    :size="16"
  >
    <n-space
      align="center"
      justify="space-between"
    >
      <h1 style="margin:0">
        Inbox
      </h1>
      <n-tag
        :type="notifications.connected ? 'success' : 'warning'"
        size="small"
      >
        WS {{ notifications.connected ? "connected" : "disconnected" }}
      </n-tag>
    </n-space>

    <n-card>
      <n-list>
        <n-list-item
          v-for="n in notifications.items"
          :key="n.id"
          style="cursor: pointer"
          @click="openItem(n.id, n.link)"
        >
          <n-thing
            :title="n.title"
            :description="fmtRelative(n.created_at)"
          >
            <template #header-extra>
              <n-badge
                v-if="!n.read_at"
                dot
                type="info"
              />
            </template>
            <p style="margin: 4px 0; color: #444">
              {{ n.body }}
            </p>
            <small style="color:#888">{{ n.kind }}</small>
          </n-thing>
        </n-list-item>
        <n-list-item v-if="!notifications.items.length">
          <n-empty description="No notifications yet" />
        </n-list-item>
      </n-list>
    </n-card>
  </n-space>
</template>
