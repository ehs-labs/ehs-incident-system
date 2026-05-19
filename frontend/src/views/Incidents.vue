<script setup lang="ts">
import { computed, h, ref, watch, onMounted } from "vue";
import { useRouter, useRoute, RouterLink } from "vue-router";
import {
  NDataTable,
  NTag,
  NInput,
  NSelect,
  NSpace,
  NCard,
  NButton,
  NPagination,
  useMessage,
  type DataTableColumns
} from "naive-ui";
import { listIncidents } from "@/api/incidents";
import { useAuthStore } from "@/stores/auth";
import type {
  IncidentAttributes,
  IncidentState,
  Severity,
  JsonApiResource,
  ApiError
} from "@/types/api";
import { fmtDate, severityColor, severityLabel, stateTagType } from "@/utils/format";

const route = useRoute();
const router = useRouter();
const message = useMessage();
const auth = useAuthStore();

interface Row extends IncidentAttributes {
  id: string;
  site_name: string;
  reporter_name: string;
}

const rows = ref<Row[]>([]);
const total = ref(0);
const loading = ref(false);

const stateOptions = [
  "draft",
  "submitted",
  "investigating",
  "pending_closure",
  "closed"
].map((s) => ({ label: s, value: s }));

const severityOptions = [1, 2, 3, 4, 5].map((s) => ({
  label: `S${s} — ${severityLabel(s)}`,
  value: s
}));

const siteOptions = computed(() =>
  auth.sites.map((s) => ({ label: s.name, value: String(s.id) }))
);

function parseArray(q: unknown): string[] {
  if (q == null) return [];
  return Array.isArray(q) ? (q as string[]) : [String(q)];
}

const filters = ref({
  state: parseArray(route.query.state) as IncidentState[],
  severity: parseArray(route.query.severity).map(Number) as Severity[],
  site_id: (route.query.site_id as string) || null,
  q: (route.query.q as string) || ""
});
const page = ref(Number(route.query.page ?? 1));
const perPage = 20;

let qTimer: number | null = null;
function onSearch(val: string) {
  filters.value.q = val;
  if (qTimer) window.clearTimeout(qTimer);
  qTimer = window.setTimeout(() => {
    page.value = 1;
    sync();
  }, 300);
}

function sync() {
  router.replace({
    query: {
      ...(filters.value.state.length && { state: filters.value.state }),
      ...(filters.value.severity.length && {
        severity: filters.value.severity.map(String)
      }),
      ...(filters.value.site_id && { site_id: filters.value.site_id }),
      ...(filters.value.q && { q: filters.value.q }),
      page: String(page.value)
    }
  });
}

async function load() {
  loading.value = true;
  try {
    const res = await listIncidents({
      state: filters.value.state.length ? filters.value.state : undefined,
      severity: filters.value.severity.length ? filters.value.severity : undefined,
      site_id: filters.value.site_id ?? undefined,
      q: filters.value.q || undefined,
      page: page.value,
      per_page: perPage
    });
    const siteName = new Map<string, string>();
    const userName = new Map<string, string>();
    for (const inc of res.data.included ?? []) {
      if (inc.type === "site")
        siteName.set(inc.id, (inc.attributes as { name: string }).name);
      if (inc.type === "user")
        userName.set(inc.id, (inc.attributes as { name: string }).name);
    }
    rows.value = res.data.data.map((r: JsonApiResource<IncidentAttributes>) => ({
      id: r.id,
      ...r.attributes,
      site_name:
        siteName.get(String(r.attributes.site_id)) ??
        `Site ${r.attributes.site_id}`,
      reporter_name:
        userName.get(String(r.attributes.reporter_id)) ??
        `User ${r.attributes.reporter_id}`
    }));
    total.value = res.total;
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed to load incidents");
  } finally {
    loading.value = false;
  }
}

watch(
  () => [filters.value.state, filters.value.severity, filters.value.site_id],
  () => {
    page.value = 1;
    sync();
  },
  { deep: true }
);
watch(page, sync);
watch(() => route.query, load);
onMounted(load);

const columns: DataTableColumns<Row> = [
  { title: "ID", key: "id", width: 70 },
  { title: "Summary", key: "summary", ellipsis: { tooltip: true } },
  { title: "Type", key: "incident_type", width: 110 },
  {
    title: "Severity",
    key: "severity",
    width: 100,
    render: (r) =>
      h(
        "span",
        {
          style: {
            display: "inline-block",
            padding: "2px 8px",
            borderRadius: "10px",
            color: "#fff",
            background: severityColor(r.severity),
            fontSize: "12px"
          }
        },
        `S${r.severity}`
      )
  },
  {
    title: "State",
    key: "state",
    width: 130,
    render: (r) =>
      h(NTag, { type: stateTagType(r.state), bordered: false }, () => r.state)
  },
  { title: "Site", key: "site_name", width: 160 },
  { title: "Reporter", key: "reporter_name", width: 160 },
  {
    title: "Occurred",
    key: "occurred_at",
    width: 150,
    render: (r) => fmtDate(r.occurred_at)
  },
  {
    title: "Triage",
    key: "triage_overdue",
    width: 100,
    render: (r) =>
      r.triage_overdue
        ? h(NTag, { type: "error", size: "small", bordered: false }, () => "overdue")
        : h("span", { style: "color:#888" }, "—")
  }
];

function rowProps(row: Row) {
  return {
    style: "cursor:pointer",
    onClick: () => router.push(`/incidents/${row.id}`)
  };
}
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
        Incidents
      </h1>
      <RouterLink to="/incidents/new">
        <n-button type="primary">
          + New Incident
        </n-button>
      </RouterLink>
    </n-space>

    <n-card>
      <n-space :wrap="true">
        <n-input
          :value="filters.q"
          placeholder="Search summary or location…"
          clearable
          style="width: 280px"
          @update:value="onSearch"
        />
        <n-select
          v-model:value="filters.state"
          multiple
          :options="stateOptions"
          placeholder="State"
          style="min-width: 200px"
          clearable
        />
        <n-select
          v-model:value="filters.severity"
          multiple
          :options="severityOptions"
          placeholder="Severity"
          style="min-width: 160px"
          clearable
        />
        <n-select
          v-model:value="filters.site_id"
          :options="siteOptions"
          placeholder="Site"
          style="min-width: 200px"
          clearable
        />
      </n-space>
    </n-card>

    <n-data-table
      :columns="columns"
      :data="rows"
      :loading="loading"
      :row-props="rowProps"
      :bordered="false"
      striped
    />

    <n-space justify="center">
      <n-pagination
        v-model:page="page"
        :page-count="Math.max(1, Math.ceil(total / perPage))"
        :page-size="perPage"
        :item-count="total"
      />
    </n-space>
  </n-space>
</template>
