<script setup lang="ts">
import { ref, computed } from "vue";
import { useRouter, RouterLink } from "vue-router";
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

const auth = useAuthStore();
const router = useRouter();

const name = ref("");
const email = ref("");
const password = ref("");
const passwordConfirmation = ref("");
const loading = ref(false);
const error = ref<{ status: number; detail: string } | null>(null);

const canSubmit = computed(
  () =>
    name.value &&
    email.value &&
    password.value.length >= 8 &&
    password.value === passwordConfirmation.value
);

async function submit() {
  error.value = null;
  loading.value = true;
  try {
    await auth.signup(
      name.value.trim(),
      email.value.trim(),
      password.value,
      passwordConfirmation.value
    );
    router.push("/dashboard");
  } catch (e) {
    const ae = e as {
      response?: { status?: number; data?: { detail?: string; title?: string } };
    };
    error.value = {
      status: ae.response?.status ?? 0,
      detail:
        ae.response?.data?.detail ??
        ae.response?.data?.title ??
        "Signup failed"
    };
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="auth-wrap">
    <n-card
      title="Create your EHS Incidents account"
      style="width: 420px"
    >
      <n-alert
        v-if="error"
        type="error"
        :title="`Error ${error.status}`"
        style="margin-bottom: 16px"
      >
        {{ error.detail }}
      </n-alert>
      <p style="color:#666; margin: 0 0 12px 0">
        Signing up creates a new organization with you as its first admin.
      </p>
      <n-form @submit.prevent="submit">
        <n-form-item label="Your name">
          <n-input v-model:value="name" />
        </n-form-item>
        <n-form-item label="Email">
          <n-input
            v-model:value="email"
            autocomplete="username"
          />
        </n-form-item>
        <n-form-item label="Password (min 8 chars)">
          <n-input
            v-model:value="password"
            type="password"
            show-password-on="click"
            autocomplete="new-password"
          />
        </n-form-item>
        <n-form-item label="Confirm password">
          <n-input
            v-model:value="passwordConfirmation"
            type="password"
            show-password-on="click"
            autocomplete="new-password"
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
            :disabled="!canSubmit"
            @click="submit"
          >
            Sign up
          </n-button>
          <RouterLink to="/login">
            Already have an account? Sign in
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
