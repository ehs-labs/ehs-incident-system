<script setup lang="ts">
import { Line } from "vue-chartjs";
import {
  Chart as ChartJS,
  Title,
  Tooltip,
  Legend,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Filler
} from "chart.js";
import { computed } from "vue";

ChartJS.register(
  Title,
  Tooltip,
  Legend,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Filler
);

const props = defineProps<{
  series: { date: string; count: number }[];
}>();

const chartData = computed(() => ({
  labels: props.series.map((p) => p.date.slice(5)),
  datasets: [
    {
      label: "Incidents",
      data: props.series.map((p) => p.count),
      borderColor: "#1976d2",
      backgroundColor: "rgba(25,118,210,0.15)",
      fill: true,
      tension: 0.25,
      pointRadius: 2
    }
  ]
}));

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: false } },
  scales: {
    y: { beginAtZero: true, ticks: { precision: 0 } }
  }
} as const;
</script>

<template>
  <div style="height: 220px">
    <Line
      :data="chartData"
      :options="chartOptions"
    />
  </div>
</template>
