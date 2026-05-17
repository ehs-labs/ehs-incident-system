<script setup lang="ts">
import { ref } from "vue";
import { useRouter, useRoute, RouterLink } from "vue-router";
import {
  NCard,
  NForm,
  NFormItem,
  NInput,
  NButton,
  NAlert,
  NSpace
} from "naive-ui";
import { useAuthStore } from "@/stores/auth";
import { ApiError } from "@/types/api";

const auth = useAuthStore();
const router = useRouter();
const route = useRoute();

const email = ref("");
const password = ref("");
const loading = ref(false);
const error = ref<{ status: number; detail: string } | null>(null);

async function submit() {
  error.value = null;
  loading.value = true;
  try {
    await auth.login(email.value.trim(), password.value);
    const next = (route.query.next as string) || "/dashboard";
    router.push(next);
  } catch (e) {
    if (e instanceof ApiError) {
      error.value = {
        status: e.status,
        detail: e.problem.detail ?? e.problem.title ?? "Login failed"
      };
    } else if (e instanceof Error && e.message.includes("Network")) {
      error.value = { status: 0, detail: "Cannot reach the API. Is it running?" };
    } else {
      // Raw axios error (login uses axios directly, not the wrapper)
      const ae = e as { response?: { status?: number; data?: { detail?: string; title?: string } } };
      error.value = {
        status: ae.response?.status ?? 0,
        detail:
          ae.response?.data?.detail ??
          ae.response?.data?.title ??
          "Login failed"
      };
    }
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="auth-wrap">
    <n-card
      title="Sign in to EHS Incidents"
      style="width: 380px"
    >
      <n-alert
        v-if="error"
        type="error"
        :title="`Error ${error.status}`"
        style="margin-bottom: 16px"
      >
        {{ error.detail }}
      </n-alert>
      <n-form @submit.prevent="submit">
        <n-form-item label="Email">
          <n-input
            v-model:value="email"
            placeholder="you@example.com"
            autocomplete="username"
            @keyup.enter="submit"
          />
        </n-form-item>
        <n-form-item label="Password">
          <n-input
            v-model:value="password"
            type="password"
            show-password-on="click"
            autocomplete="current-password"
            @keyup.enter="submit"
          />
        </n-form-item>
        <n-space
          vertical
          :size="12"
        >
          <n-button
            type="primary"
            block
            :loading="loading"
            :disabled="!email || !password"
            @click="submit"
          >
            Sign in
          </n-button>
          <RouterLink to="/signup">
            Need an account? Sign up
          </RouterLink>
        </n-space>
      </n-form>
    </n-card>
  </div>
</template>

<style scoped>
.auth-wrap {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #f4f5f7;
  padding: 16px;
}
</style>
