<script setup lang="ts">
import { NCard, NDescriptions, NDescriptionsItem, NSpace, NTag } from "naive-ui";
import { useAuthStore } from "@/stores/auth";

const auth = useAuthStore();
</script>

<template>
  <n-space
    vertical
    :size="16"
  >
    <h1 style="margin:0">
      My profile
    </h1>
    <n-card>
      <n-descriptions
        :column="1"
        bordered
        label-placement="left"
      >
        <n-descriptions-item label="Name">
          {{ auth.user?.name }}
        </n-descriptions-item>
        <n-descriptions-item label="Email">
          {{ auth.user?.email }}
        </n-descriptions-item>
        <n-descriptions-item label="Role">
          {{ auth.user?.role }}
        </n-descriptions-item>
        <n-descriptions-item label="Organization">
          {{ auth.organization?.name ?? "—" }}
        </n-descriptions-item>
        <n-descriptions-item label="Sites">
          <n-space>
            <n-tag
              v-for="s in auth.sites"
              :key="s.id"
              :bordered="false"
            >
              {{ s.name }} ({{ s.timezone }})
            </n-tag>
            <span
              v-if="!auth.sites.length"
              style="color:#888"
            >—</span>
          </n-space>
        </n-descriptions-item>
      </n-descriptions>
    </n-card>
  </n-space>
</template>
