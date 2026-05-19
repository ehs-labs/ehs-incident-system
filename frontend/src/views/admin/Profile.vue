<script setup lang="ts">
import { ref } from "vue";
import {
  NCard,
  NDescriptions,
  NDescriptionsItem,
  NSpace,
  NTag,
  NButton,
  NInput,
  useMessage
} from "naive-ui";
import { useAuthStore } from "@/stores/auth";
import { api } from "@/api/axios";
import { ApiError } from "@/types/api";

const auth = useAuthStore();
const message = useMessage();

const editing = ref(false);
const draftName = ref(auth.user?.name ?? "");
const saving = ref(false);

function startEdit() {
  draftName.value = auth.user?.name ?? "";
  editing.value = true;
}

function cancelEdit() {
  editing.value = false;
}

async function saveName() {
  const trimmed = draftName.value.trim();
  if (!trimmed) {
    message.error("Name cannot be empty");
    return;
  }
  saving.value = true;
  try {
    await api.patch("/me", { me: { name: trimmed } });
    await auth.fetchMe();
    editing.value = false;
    message.success("Name updated");
  } catch (e) {
    const ae = e as ApiError;
    message.error(`Could not update name: ${ae.problem?.detail ?? ae.message}`);
  } finally {
    saving.value = false;
  }
}
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
          <template v-if="editing">
            <n-space :size="8">
              <n-input
                v-model:value="draftName"
                placeholder="Your name"
                :disabled="saving"
                style="width: 280px"
                @keyup.enter="saveName"
              />
              <n-button
                type="primary"
                size="small"
                :loading="saving"
                @click="saveName"
              >
                Save
              </n-button>
              <n-button
                size="small"
                :disabled="saving"
                @click="cancelEdit"
              >
                Cancel
              </n-button>
            </n-space>
          </template>
          <template v-else>
            <n-space
              align="center"
              :size="12"
            >
              <span>{{ auth.user?.name || "—" }}</span>
              <n-button
                size="tiny"
                tertiary
                @click="startEdit"
              >
                Edit
              </n-button>
            </n-space>
          </template>
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
