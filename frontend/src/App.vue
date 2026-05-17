<script setup lang="ts">
import { NConfigProvider, NMessageProvider, NNotificationProvider, NDialogProvider } from "naive-ui";
</script>

<template>
  <n-config-provider>
    <n-message-provider>
      <n-notification-provider>
        <n-dialog-provider>
          <router-view />
        </n-dialog-provider>
      </n-notification-provider>
    </n-message-provider>
  </n-config-provider>
</template>
