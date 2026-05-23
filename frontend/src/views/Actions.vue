<script setup lang="ts">
import { computed, h, onMounted, ref } from "vue";
import {
  NDataTable,
  NTag,
  NSpace,
  NButton,
  NCard,
  NModal,
  NInput,
  useMessage,
  type DataTableColumns
} from "naive-ui";
import { useRouter } from "vue-router";
import { listActions, transitionAction, type ActionTransition } from "@/api/actions";
import { useAuthStore } from "@/stores/auth";
import { fmtDate, actionStateTagType } from "@/utils/format";
import { allowedActionTransitions } from "@/utils/permissions";
import type {
  CorrectiveActionAttributes,
  ApiError
} from "@/types/api";

const auth = useAuthStore();
const router = useRouter();
const message = useMessage();

interface Row extends CorrectiveActionAttributes {
  id: string;
}
const rows = ref<Row[]>([]);
const loading = ref(true);

async function load() {
  if (!auth.user) return;
  loading.value = true;
  try {
    const res = await listActions({ assignee_id: auth.user.id });
    rows.value = res.data.map((r) => ({ id: r.id, ...r.attributes }));
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed to load actions");
  } finally {
    loading.value = false;
  }
}

// Every transition opens this dialog so the operator can attach an optional
// note. Mirrors the same flow used on the incident detail page so the worker
// can hand off context (e.g. "replaced wheel, bearing also worn") without
// switching views.
const TRANSITION_TITLES: Record<ActionTransition, string> = {
  start:    "Start action",
  complete: "Mark as done",
  verify:   "Verify action",
  cancel:   "Cancel action"
};
const transitionDialog = ref<{
  show: boolean;
  actionId: string | null;
  event: ActionTransition | null;
  note: string;
}>({ show: false, actionId: null, event: null, note: "" });

const transitionDialogTitle = computed(() =>
  transitionDialog.value.event ? TRANSITION_TITLES[transitionDialog.value.event] : ""
);

function openTransitionDialog(actionId: string, event: ActionTransition) {
  transitionDialog.value = { show: true, actionId, event, note: "" };
}

async function confirmTransition() {
  const { actionId, event, note } = transitionDialog.value;
  if (!actionId || !event) return;
  try {
    await transitionAction(actionId, event, note || undefined);
    transitionDialog.value.show = false;
    message.success(`Action ${event}`);
    await load();
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed");
  }
}

onMounted(load);

const columns = computed<DataTableColumns<Row>>(() => [
  { title: "Title", key: "title", ellipsis: { tooltip: true } },
  {
    title: "Incident",
    key: "incident_id",
    width: 120,
    render: (r) =>
      h(
        NButton,
        {
          text: true,
          type: "primary",
          onClick: () => router.push(`/incidents/${r.incident_id}`)
        },
        () => `#${r.incident_id}`
      )
  },
  { title: "Due", key: "due_date", width: 170, render: (r) => fmtDate(r.due_date) },
  {
    title: "State",
    key: "state",
    width: 130,
    render: (r) =>
      h(NTag, { type: actionStateTagType(r.state), bordered: false }, () => r.state)
  },
  {
    title: "Overdue",
    key: "overdue",
    width: 100,
    render: (r) =>
      r.overdue
        ? h(NTag, { type: "error", size: "small", bordered: false }, () => "yes")
        : h("span", { style: "color:#888" }, "—")
  },
  {
    title: "Actions",
    key: "x_actions",
    width: 240,
    render: (r) => {
      const events = allowedActionTransitions(
        r.state,
        auth.user?.role ?? "worker",
        String(r.assignee_id) === auth.user?.id
      );
      return h(
        NSpace,
        {},
        () =>
          events.map((ev) =>
            h(
              NButton,
              {
                size: "small",
                onClick: () => openTransitionDialog(r.id, ev)
              },
              () => ev
            )
          )
      );
    }
  }
]);
</script>

<template>
  <n-space
    vertical
    :size="16"
  >
    <h1 style="margin:0">
      My Actions
    </h1>
    <n-card>
      <n-data-table
        :columns="columns"
        :data="rows"
        :loading="loading"
        :bordered="false"
        striped
      />
    </n-card>

    <n-modal
      v-model:show="transitionDialog.show"
      preset="dialog"
      :title="transitionDialogTitle"
      positive-text="Confirm"
      negative-text="Cancel"
      @positive-click="confirmTransition"
      @negative-click="transitionDialog.show = false"
    >
      <n-input
        v-model:value="transitionDialog.note"
        type="textarea"
        :autosize="{ minRows: 2, maxRows: 6 }"
        placeholder="Optional note"
      />
    </n-modal>
  </n-space>
</template>
