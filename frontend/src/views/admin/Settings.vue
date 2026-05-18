<script setup lang="ts">
import { onMounted, ref } from "vue";
import {
  NCard,
  NForm,
  NFormItem,
  NButton,
  NSpace,
  NAlert,
  useMessage
} from "naive-ui";
import { getSettings, updateSettings } from "@/api/admin";
import { humanizeSeconds } from "@/utils/format";
import type { ApiError } from "@/types/api";
import DurationInput from "@/components/DurationInput.vue";

const message = useMessage();
const error = ref<string | null>(null);
const loading = ref(true);

const overrides = ref<Record<string, number>>({
  "1": 7200,
  "2": 14400,
  "3": 28800,
  "4": 86400,
  "5": 172800
});

async function load() {
  loading.value = true;
  try {
    const res = await getSettings();
    const existing = res.data.attributes.sla_overrides ?? {};
    for (const sev of ["1", "2", "3", "4", "5"]) {
      if (existing[sev]?.triage_seconds != null)
        overrides.value[sev] = existing[sev].triage_seconds;
    }
  } catch (e) {
    error.value = (e as ApiError).message;
  } finally {
    loading.value = false;
  }
}

async function save() {
  try {
    const payload: Record<string, { triage_seconds: number }> = {};
    for (const [sev, secs] of Object.entries(overrides.value)) {
      payload[sev] = { triage_seconds: secs };
    }
    await updateSettings(payload);
    message.success("Saved");
  } catch (e) {
    error.value = (e as ApiError).message;
  }
}

onMounted(load);
</script>

<template>
  <n-space
    vertical
    :size="16"
  >
    <h1 style="margin:0">
      SLA settings
    </h1>
    <n-alert
      v-if="error"
      type="error"
      closable
      @close="error = null"
    >
      {{ error }}
    </n-alert>
    <n-card title="Triage deadlines by severity">
      <p style="color:#666; margin-top:0">
        Time from submission until the incident is considered overdue for triage.
      </p>
      <n-form v-if="!loading">
        <n-form-item
          v-for="sev in ['1','2','3','4','5']"
          :key="sev"
          :label="`Severity ${sev}`"
        >
          <n-space :size="12" align="center">
            <duration-input v-model="overrides[sev]" />
            <span style="color: #666">
              = {{ humanizeSeconds(overrides[sev]) }}
            </span>
          </n-space>
        </n-form-item>
        <n-button
          type="primary"
          @click="save"
        >
          Save
        </n-button>
      </n-form>
    </n-card>
  </n-space>
</template>
