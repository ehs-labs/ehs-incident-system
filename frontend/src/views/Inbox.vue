<script setup lang="ts">
import {
  NList,
  NListItem,
  NEmpty,
  NSpace,
  NBadge,
  NTag,
  NCard,
  NButton
} from "naive-ui";
import { useRouter } from "vue-router";
import { useNotificationStore, type Notification } from "@/composables/useNotifications";
import { fmtRelative } from "@/utils/format";

const router = useRouter();
const notifications = useNotificationStore();

// Friendly labels and tag colors per event_type. Unknown event types fall back
// to a neutral tag with the raw event_type as the label.
const EVENT_LABEL: Record<string, string> = {
  IncidentSubmitted: "New incident",
  IncidentAssigned: "Assigned to you",
  IncidentClosed: "Incident closed",
  CorrectiveActionAssigned: "Action assigned",
  CorrectiveActionOverdue: "Action overdue",
  SlaBreached: "SLA breached"
};
const EVENT_TAG_TYPE: Record<
  string,
  "default" | "info" | "success" | "warning" | "error"
> = {
  IncidentSubmitted: "info",
  IncidentAssigned: "info",
  IncidentClosed: "success",
  CorrectiveActionAssigned: "info",
  CorrectiveActionOverdue: "warning",
  SlaBreached: "error"
};

function eventLabel(t: string): string {
  return EVENT_LABEL[t] ?? t;
}
function tagType(t: string) {
  return EVENT_TAG_TYPE[t] ?? "default";
}

function openLink(n: Notification) {
  notifications.markRead(n.id);
  if (n.link) router.push(n.link);
}
function markRead(n: Notification) {
  notifications.markRead(n.id);
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
        >
          <div class="inbox-item">
            <div class="inbox-header">
              <span class="inbox-title">{{ n.title }}</span>
              <n-tag
                size="small"
                :type="tagType(n.event_type)"
                :bordered="false"
              >
                {{ eventLabel(n.event_type) }}
              </n-tag>
              <n-badge
                v-if="!n.read_at"
                dot
                type="info"
              />
              <span class="inbox-time">{{ fmtRelative(n.created_at) }}</span>
            </div>
            <p class="inbox-body">
              {{ n.body }}
            </p>
            <n-space :size="8">
              <n-button
                v-if="n.link"
                size="small"
                tertiary
                @click="openLink(n)"
              >
                Open incident
              </n-button>
              <n-button
                v-if="!n.read_at"
                size="small"
                quaternary
                @click="markRead(n)"
              >
                Mark as read
              </n-button>
            </n-space>
          </div>
        </n-list-item>
        <n-list-item v-if="!notifications.items.length">
          <n-empty description="No notifications yet" />
        </n-list-item>
      </n-list>
    </n-card>
  </n-space>
</template>

<style scoped>
.inbox-item {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 4px 0;
}
.inbox-header {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}
.inbox-title {
  font-weight: 600;
  font-size: 14px;
}
.inbox-time {
  margin-left: auto;
  font-size: 12px;
  color: #888;
}
.inbox-body {
  margin: 0;
  color: #333;
  font-size: 14px;
  line-height: 1.5;
}
</style>
