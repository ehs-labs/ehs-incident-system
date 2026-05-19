<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
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
import { listOrgUsers, updateUser } from "@/api/admin";
import type { Role, ApiError } from "@/types/api";

const route = useRoute();
const router = useRouter();
const message = useMessage();

const form = ref({ name: "", role: "worker" as Role });
const loading = ref(false);
const error = ref<string | null>(null);

const roleOptions: { label: string; value: Role }[] = [
  { label: "Worker", value: "worker" },
  { label: "Investigator", value: "investigator" },
  { label: "Admin", value: "admin" }
];

onMounted(async () => {
  try {
    const list = await listOrgUsers();
    const found = list.data.find((r) => r.id === route.params.id);
    if (found) {
      form.value = {
        name: found.attributes.name ?? "",
        role: found.attributes.role ?? "worker"
      };
    }
  } catch (e) {
    error.value = (e as ApiError).message;
  }
});

async function submit() {
  loading.value = true;
  error.value = null;
  try {
    await updateUser(String(route.params.id), form.value);
    message.success("Saved");
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
      Edit user
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
            Save
          </n-button>
          <n-button @click="router.push('/admin/users')">
            Cancel
          </n-button>
        </n-space>
      </n-form>
    </n-card>
  </n-space>
</template>
