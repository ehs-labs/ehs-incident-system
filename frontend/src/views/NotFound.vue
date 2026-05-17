<script setup lang="ts">
import { NResult, NButton } from "naive-ui";
import { useRouter } from "vue-router";

const router = useRouter();
</script>

<template>
  <div style="display:flex; min-height: 60vh; align-items:center; justify-content:center">
    <n-result
      status="404"
      title="Page not found"
      description="That route doesn't exist."
    >
      <template #footer>
        <n-button
          type="primary"
          @click="router.push('/dashboard')"
        >
          Go to dashboard
        </n-button>
      </template>
    </n-result>
  </div>
</template>
