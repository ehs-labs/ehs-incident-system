<script setup lang="ts">
import { computed } from "vue";
import { NInputNumber, NSpace } from "naive-ui";

// Edits a duration stored in seconds via three side-by-side number inputs
// (days, hours, minutes). Emits the recomputed total in seconds on every
// change, so the parent's model stays canonical and the wire format unchanged.
//
// Why no library: humanize-duration is display-only; date-fns can format but
// doesn't ship an editor. The whole thing is ~30 lines — not worth a dep.

const props = defineProps<{
  modelValue: number; // seconds
}>();

const emit = defineEmits<{
  "update:modelValue": [value: number];
}>();

const SECONDS_PER_DAY    = 86_400;
const SECONDS_PER_HOUR   = 3_600;
const SECONDS_PER_MINUTE = 60;

function partsFromSeconds(total: number) {
  const safe = Math.max(0, Math.floor(total ?? 0));
  return {
    days:    Math.floor(safe / SECONDS_PER_DAY),
    hours:   Math.floor((safe % SECONDS_PER_DAY) / SECONDS_PER_HOUR),
    minutes: Math.floor((safe % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
  };
}

const parts = computed(() => partsFromSeconds(props.modelValue));

function update(field: "days" | "hours" | "minutes", value: number | null) {
  const next = {
    days: parts.value.days,
    hours: parts.value.hours,
    minutes: parts.value.minutes,
    [field]: Math.max(0, value ?? 0)
  };
  emit(
    "update:modelValue",
    next.days * SECONDS_PER_DAY +
      next.hours * SECONDS_PER_HOUR +
      next.minutes * SECONDS_PER_MINUTE
  );
}
</script>

<template>
  <n-space
    :size="8"
    align="center"
  >
    <n-input-number
      :value="parts.days"
      :min="0"
      :show-button="true"
      style="width: 100px"
      @update:value="(v: number | null) => update('days', v)"
    >
      <template #suffix>
        d
      </template>
    </n-input-number>
    <n-input-number
      :value="parts.hours"
      :min="0"
      :max="23"
      :show-button="true"
      style="width: 100px"
      @update:value="(v: number | null) => update('hours', v)"
    >
      <template #suffix>
        h
      </template>
    </n-input-number>
    <n-input-number
      :value="parts.minutes"
      :min="0"
      :max="59"
      :show-button="true"
      style="width: 100px"
      @update:value="(v: number | null) => update('minutes', v)"
    >
      <template #suffix>
        m
      </template>
    </n-input-number>
  </n-space>
</template>
