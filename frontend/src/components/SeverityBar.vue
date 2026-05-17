<script setup lang="ts">
import { computed } from "vue";
import { NTooltip } from "naive-ui";
import { severityColor, severityLabel } from "@/utils/format";

const props = defineProps<{
  distribution: Record<string, number>;
}>();

const total = computed(() =>
  Object.values(props.distribution).reduce((acc, n) => acc + (n ?? 0), 0)
);

const segments = computed(() =>
  ([1, 2, 3, 4, 5] as const).map((sev) => {
    const count = props.distribution[String(sev)] ?? 0;
    const pct = total.value > 0 ? (count / total.value) * 100 : 0;
    return { sev, count, pct };
  })
);
</script>

<template>
  <div>
    <div class="bar">
      <n-tooltip
        v-for="seg in segments"
        :key="seg.sev"
        :disabled="seg.count === 0"
        placement="top"
      >
        <template #trigger>
          <div
            class="seg"
            :style="{
              flexBasis: `${seg.pct}%`,
              backgroundColor: severityColor(seg.sev),
              minWidth: seg.count > 0 ? '6px' : '0'
            }"
          />
        </template>
        {{ severityLabel(seg.sev) }}: {{ seg.count }}
      </n-tooltip>
    </div>
    <div class="legend">
      <span
        v-for="seg in segments"
        :key="seg.sev"
        class="leg-item"
      >
        <span
          class="dot"
          :style="{ backgroundColor: severityColor(seg.sev) }"
        />
        {{ severityLabel(seg.sev) }} ({{ seg.count }})
      </span>
    </div>
  </div>
</template>

<style scoped>
.bar {
  display: flex;
  width: 100%;
  height: 14px;
  border-radius: 7px;
  overflow: hidden;
  background: #eee;
}
.seg {
  height: 100%;
  transition: flex-basis 0.3s ease;
}
.legend {
  margin-top: 8px;
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  font-size: 12px;
  color: #555;
}
.leg-item {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  display: inline-block;
}
</style>
