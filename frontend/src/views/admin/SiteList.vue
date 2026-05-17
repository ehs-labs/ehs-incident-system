<script setup lang="ts">
import { h, onMounted, ref } from "vue";
import {
  NDataTable,
  NSpace,
  NButton,
  NCard,
  NModal,
  NForm,
  NFormItem,
  NInput,
  NAutoComplete,
  NPopconfirm,
  useMessage,
  type DataTableColumns
} from "naive-ui";
import {
  listAdminSites,
  createSite,
  updateSite,
  deleteSite
} from "@/api/admin";
import type { Site, ApiError } from "@/types/api";

const message = useMessage();
const rows = ref<(Site & { id: string })[]>([]);
const loading = ref(true);

const showModal = ref(false);
const editing = ref<{ id: string | null; name: string; timezone: string }>({
  id: null,
  name: "",
  timezone: "UTC"
});

// Small curated IANA list for autocomplete; the input is free-text so anything works.
const tzList = [
  "UTC",
  "Australia/Sydney",
  "Australia/Melbourne",
  "Australia/Perth",
  "Australia/Brisbane",
  "Australia/Adelaide",
  "Europe/London",
  "Europe/Berlin",
  "Europe/Paris",
  "Europe/Madrid",
  "Europe/Moscow",
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Sao_Paulo",
  "Asia/Tokyo",
  "Asia/Shanghai",
  "Asia/Singapore",
  "Asia/Dubai",
  "Pacific/Auckland"
];

async function load() {
  loading.value = true;
  try {
    const res = await listAdminSites();
    rows.value = res.data.map((r) => ({
      ...(r.attributes as Site),
      id: r.id
    }));
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed");
  } finally {
    loading.value = false;
  }
}

function openCreate() {
  editing.value = { id: null, name: "", timezone: "UTC" };
  showModal.value = true;
}
function openEdit(r: Site & { id: string }) {
  editing.value = { id: r.id, name: r.name, timezone: r.timezone };
  showModal.value = true;
}

async function save() {
  try {
    if (editing.value.id)
      await updateSite(editing.value.id, {
        name: editing.value.name,
        timezone: editing.value.timezone
      });
    else
      await createSite({
        name: editing.value.name,
        timezone: editing.value.timezone
      });
    message.success("Saved");
    showModal.value = false;
    await load();
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed");
  }
}

async function remove(id: string) {
  try {
    await deleteSite(id);
    message.success("Deleted");
    await load();
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed");
  }
}

onMounted(load);

const columns: DataTableColumns<Site & { id: string }> = [
  { title: "Name", key: "name" },
  { title: "Timezone", key: "timezone" },
  {
    title: "Actions",
    key: "x",
    render: (r) =>
      h(NSpace, {}, () => [
        h(NButton, { size: "small", onClick: () => openEdit(r) }, () => "Edit"),
        h(
          NPopconfirm,
          { onPositiveClick: () => remove(r.id) },
          {
            trigger: () =>
              h(NButton, { size: "small", type: "error" }, () => "Delete"),
            default: () => "Delete this site?"
          }
        )
      ])
  }
];
</script>

<template>
  <n-space
    vertical
    :size="16"
  >
    <n-space
      justify="space-between"
      align="center"
    >
      <h1 style="margin:0">
        Sites
      </h1>
      <n-button
        type="primary"
        @click="openCreate"
      >
        + New site
      </n-button>
    </n-space>
    <n-card>
      <n-data-table
        :columns="columns"
        :data="rows"
        :loading="loading"
        :bordered="false"
      />
    </n-card>

    <n-modal
      v-model:show="showModal"
      preset="card"
      :title="editing.id ? 'Edit site' : 'New site'"
      style="width: 480px"
    >
      <n-form>
        <n-form-item label="Name">
          <n-input v-model:value="editing.name" />
        </n-form-item>
        <n-form-item label="Timezone (IANA)">
          <n-auto-complete
            v-model:value="editing.timezone"
            :options="tzList.map((t) => ({ label: t, value: t }))"
            placeholder="e.g. Australia/Sydney"
          />
        </n-form-item>
        <n-space justify="end">
          <n-button @click="showModal = false">
            Cancel
          </n-button>
          <n-button
            type="primary"
            @click="save"
          >
            Save
          </n-button>
        </n-space>
      </n-form>
    </n-modal>
  </n-space>
</template>
