<script setup lang="ts">
import { onMounted, ref, computed } from "vue";
import {
  NCard,
  NGrid,
  NGi,
  NStatistic,
  NSkeleton,
  NSpace,
  NTag,
  NButton,
  useMessage
} from "naive-ui";
import { RouterLink } from "vue-router";
import { getDashboard } from "@/api/dashboard";
import type { DashboardAttributes, ApiError } from "@/types/api";
import { humanizeSeconds } from "@/utils/format";
import SeverityBar from "@/components/SeverityBar.vue";
import TrendChart from "@/components/TrendChart.vue";

const message = useMessage();
const data = ref<DashboardAttributes | null>(null);
const loading = ref(true);

const openTotal = computed(() =>
  data.value
    ? Object.values(data.value.open_incidents_by_severity).reduce(
        (a, n) => a + (n ?? 0),
        0
      )
    : 0
);

const slaCompliance = computed(() => {
  const s = data.value?.sla_compliance ?? {};
  const total = (s.on_time ?? 0) + (s.breached ?? 0) + (s.pending ?? 0);
  const pct = total > 0 ? Math.round(((s.on_time ?? 0) / total) * 100) : null;
  return { ...s, total, pct };
});

async function load() {
  loading.value = true;
  try {
    const res = await getDashboard();
    data.value = res.data.attributes;
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed to load dashboard");
  } finally {
    loading.value = false;
  }
}

onMounted(load);
</script>

<template>
  <n-space
    vertical
    :size="20"
    style="width: 100%"
  >
    <n-space
      align="center"
      justify="space-between"
    >
      <h1 style="margin: 0">
        Dashboard
      </h1>
      <RouterLink to="/incidents/new">
        <n-button type="primary">
          + New Incident
        </n-button>
      </RouterLink>
    </n-space>

    <template v-if="loading">
      <n-grid
        :cols="4"
        :x-gap="16"
        :y-gap="16"
        responsive="screen"
      >
        <n-gi
          v-for="i in 4"
          :key="i"
        >
          <n-card>
            <n-skeleton
              text
              :repeat="3"
            />
          </n-card>
        </n-gi>
      </n-grid>
    </template>

    <template v-else-if="data">
      <n-grid
        :cols="4"
        :x-gap="16"
        :y-gap="16"
        responsive="screen"
        item-responsive
      >
        <n-gi span="4 m:2 l:1">
          <n-card>
            <n-statistic
              label="Open incidents"
              :value="openTotal"
            />
          </n-card>
        </n-gi>
        <n-gi span="4 m:2 l:1">
          <n-card>
            <n-statistic
              label="Overdue actions"
              :value="data.overdue_corrective_actions_count"
            />
          </n-card>
        </n-gi>
        <n-gi span="4 m:2 l:1">
          <n-card>
            <n-statistic
              label="Avg time-to-close"
              :value="humanizeSeconds(data.avg_time_to_close_seconds)"
            />
          </n-card>
        </n-gi>
        <n-gi span="4 m:2 l:1">
          <n-card>
            <n-statistic
              label="SLA compliance"
              :value="slaCompliance.pct == null ? '—' : `${slaCompliance.pct}%`"
            />
            <n-space
              :size="6"
              style="margin-top: 6px; font-size: 12px; color: #666"
            >
              <n-tag
                size="small"
                type="success"
              >
                on-time {{ slaCompliance.on_time ?? 0 }}
              </n-tag>
              <n-tag
                size="small"
                type="error"
              >
                breached {{ slaCompliance.breached ?? 0 }}
              </n-tag>
              <n-tag size="small">
                pending {{ slaCompliance.pending ?? 0 }}
              </n-tag>
            </n-space>
          </n-card>
        </n-gi>
      </n-grid>

      <n-grid
        :cols="2"
        :x-gap="16"
        :y-gap="16"
        responsive="screen"
      >
        <n-gi span="2 m:1">
          <n-card title="Severity distribution (open)">
            <severity-bar :distribution="data.open_incidents_by_severity" />
          </n-card>
        </n-gi>
        <n-gi span="2 m:1">
          <n-card title="Incidents by state">
            <n-space :size="8">
              <n-tag
                v-for="(count, state) in data.incidents_by_state"
                :key="state"
                :bordered="false"
              >
                {{ state }}: {{ count }}
              </n-tag>
            </n-space>
          </n-card>
        </n-gi>
      </n-grid>

      <n-card title="Last 30 days — new incidents">
        <trend-chart :series="data.last_30_day_incidents_trend" />
      </n-card>
    </template>
  </n-space>
</template>
