<script setup lang="ts">
import { NResult, NButton } from "naive-ui";
import { RouterLink } from "vue-router";
</script>

<template>
  <div style="display:flex; min-height: 100vh; align-items:center; justify-content:center; background:#f4f5f7">
    <n-result
      status="info"
      title="Password reset"
      description="Password reset is not enabled in this MVP. For the demo, please use the seeded accounts."
    >
      <template #footer>
        <RouterLink to="/login">
          <n-button type="primary">
            Back to login
          </n-button>
        </RouterLink>
      </template>
    </n-result>
  </div>
</template>
