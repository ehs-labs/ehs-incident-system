<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import {
  NCard,
  NForm,
  NFormItem,
  NInput,
  NSelect,
  NButton,
  NSpace,
  NAlert,
  useMessage
} from "naive-ui";
import { inviteUser } from "@/api/admin";
import type { Role, ApiError } from "@/types/api";

const router = useRouter();
const message = useMessage();

const form = ref({ name: "", email: "", role: "worker" as Role });
const loading = ref(false);
const error = ref<string | null>(null);

const roleOptions: { label: string; value: Role }[] = [
  { label: "Worker", value: "worker" },
  { label: "Investigator", value: "investigator" },
  { label: "Admin", value: "admin" }
];

async function submit() {
  loading.value = true;
  error.value = null;
  try {
    await inviteUser(form.value);
    message.success("User invited");
    router.push("/admin/users");
  } catch (e) {
    error.value = (e as ApiError).problem?.detail ?? (e as ApiError).message;
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <n-space
    vertical
    :size="16"
  >
    <h1 style="margin:0">
      Invite user
    </h1>
    <n-alert
      v-if="error"
      type="error"
      closable
      @close="error = null"
    >
      {{ error }}
    </n-alert>
    <n-card>
      <n-form>
        <n-form-item label="Name">
          <n-input v-model:value="form.name" />
        </n-form-item>
        <n-form-item label="Email">
          <n-input v-model:value="form.email" />
        </n-form-item>
        <n-form-item label="Role">
          <n-select
            v-model:value="form.role"
            :options="roleOptions"
          />
        </n-form-item>
        <n-space>
          <n-button
            :loading="loading"
            type="primary"
            @click="submit"
          >
            Invite
          </n-button>
          <n-button @click="router.push('/admin/users')">
            Cancel
          </n-button>
        </n-space>
      </n-form>
    </n-card>
  </n-space>
</template>
