<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import {
  NSpace,
  NTag,
  NCard,
  NTabs,
  NTabPane,
  NButton,
  NSpin,
  NEmpty,
  NDescriptions,
  NDescriptionsItem,
  NInput,
  NSelect,
  NDatePicker,
  NForm,
  NFormItem,
  NUpload,
  NImage,
  NImageGroup,
  NList,
  NListItem,
  NThing,
  NPopconfirm,
  useMessage
} from "naive-ui";
import {
  getIncident,
  transitionIncident,
  updateIncident,
  listWitnesses,
  addWitness,
  listComments,
  addComment,
  listVersions,
  listAttachments,
  uploadAttachment,
  listIncidentActions,
  createIncidentAction
} from "@/api/incidents";
import { transitionAction, listActionEvents, type ActionTransition } from "@/api/actions";
import type { CorrectiveActionEventAttributes } from "@/types/api";
import { listAssignableUsers } from "@/api/users";
import { useAuthStore } from "@/stores/auth";
import { findIncluded } from "@/utils/jsonapi";
import {
  fmtDate,
  fmtRelative,
  severityColor,
  severityLabel,
  stateTagType,
  actionStateTagType,
  absoluteApiUrl
} from "@/utils/format";
import {
  allowedIncidentTransitions,
  allowedActionTransitions,
  canEditIncident
} from "@/utils/permissions";
import type {
  IncidentAttributes,
  CorrectiveActionAttributes,
  CommentAttributes,
  VersionAttributes,
  WitnessAttributes,
  AttachmentAttributes,
  User,
  Site,
  ApiError,
  JsonApiSingle
} from "@/types/api";
import type { IncidentTransition } from "@/api/incidents";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const message = useMessage();

const incidentId = computed(() => String(route.params.id));

const loading = ref(true);
const incident = ref<JsonApiSingle<IncidentAttributes> | null>(null);
const witnesses = ref<{ id: string; attrs: WitnessAttributes }[]>([]);
const comments = ref<{ id: string; attrs: CommentAttributes; author?: string }[]>([]);
const versions = ref<{ id: string; attrs: VersionAttributes }[]>([]);
const attachments = ref<{ id: string; attrs: AttachmentAttributes }[]>([]);
const actions = ref<{ id: string; attrs: CorrectiveActionAttributes }[]>([]);
const orgUsers = ref<{ id: string; name: string; email: string; role: string }[]>([]);

const tab = ref<string>("details");

const attrs = computed(() => incident.value?.data.attributes ?? null);
const site = computed(() => {
  if (!incident.value || !attrs.value) return null;
  return findIncluded<Site>(incident.value, "site", attrs.value.site_id);
});
const reporter = computed(() => {
  if (!incident.value || !attrs.value) return null;
  return findIncluded<User>(incident.value, "user", attrs.value.reporter_id);
});
const assignee = computed(() => {
  if (!incident.value || !attrs.value) return null;
  return findIncluded<User>(incident.value, "user", attrs.value.assignee_id);
});

const isReporter = computed(
  () => !!attrs.value && String(attrs.value.reporter_id) === auth.user?.id
);
const isAssignee = computed(
  () =>
    !!attrs.value && attrs.value.assignee_id != null &&
    String(attrs.value.assignee_id) === auth.user?.id
);

const transitions = computed(() => {
  if (!attrs.value || !auth.user) return [] as IncidentTransition[];
  return allowedIncidentTransitions(
    attrs.value.state,
    auth.user.role,
    isReporter.value,
    isAssignee.value
  );
});

const editable = computed(
  () =>
    !!attrs.value && !!auth.user && canEditIncident(attrs.value.state, auth.user.role)
);

const transitionLabel: Record<IncidentTransition, string> = {
  submit: "Submit",
  triage: "Triage (assign me)",
  reject: "Reject",
  actions_assigned: "Send for verification",
  verify: "Verify & close",
  reopen: "Reopen",
  edit: "Edit"
};

// ---- loaders ---------------------------------------------------------------

async function loadIncident() {
  loading.value = true;
  try {
    incident.value = await getIncident(incidentId.value);
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed to load incident");
  } finally {
    loading.value = false;
  }
}

async function loadAux() {
  try {
    const [w, c, v, a, ca] = await Promise.all([
      listWitnesses(incidentId.value),
      listComments(incidentId.value),
      listVersions(incidentId.value),
      listAttachments(incidentId.value),
      listIncidentActions(incidentId.value)
    ]);
    witnesses.value = w.data.map((r) => ({ id: r.id, attrs: r.attributes }));
    const userById = new Map<string, string>();
    for (const inc of c.included ?? []) {
      if (inc.type === "user")
        userById.set(inc.id, (inc.attributes as { name?: string }).name ?? inc.id);
    }
    comments.value = c.data.map((r) => ({
      id: r.id,
      attrs: r.attributes,
      author: userById.get(String(r.attributes.author_id))
    }));
    versions.value = v.data.map((r) => ({ id: r.id, attrs: r.attributes }));
    attachments.value = a.data.map((r) => ({ id: r.id, attrs: r.attributes }));
    actions.value = ca.data.map((r) => ({ id: r.id, attrs: r.attributes }));
  } catch (e) {
    // non-fatal; show toast
    message.warning(
      `Some details failed to load: ${(e as ApiError).message ?? "unknown error"}`
    );
  }
}

async function loadOrgUsers() {
  if (auth.user?.role !== "admin" && auth.user?.role !== "investigator") return;
  try {
    const res = await listAssignableUsers();
    orgUsers.value = res.data.map((r) => ({
      id: r.id,
      name: r.attributes.name ?? "",
      email: r.attributes.email ?? "",
      role: r.attributes.role ?? "worker"
    }));
  } catch (e) {
    message.error(
      `Could not load assignee list: ${(e as ApiError).message ?? "unknown error"}`
    );
  }
}

watch(incidentId, async () => {
  await loadIncident();
  await loadAux();
});
onMounted(async () => {
  await loadIncident();
  await loadAux();
  await loadOrgUsers();
});

// ---- transition button -----------------------------------------------------

async function doTransition(event: IncidentTransition) {
  try {
    // For "triage" we also assign to current user as a convenience.
    if (event === "triage" && auth.user) {
      await updateIncident(incidentId.value, { assignee_id: Number(auth.user.id) });
    }
    const res = await transitionIncident(incidentId.value, event);
    incident.value = res;
    message.success(`Transitioned: ${event}`);
    await loadAux();
  } catch (e) {
    const ae = e as ApiError;
    message.error(`Transition failed: ${ae.problem?.detail ?? ae.message}`);
  }
}

// ---- editable fields -------------------------------------------------------

const editBuffer = ref<{
  location: string;
  description: string;
  assignee_id: number | null;
}>({ location: "", description: "", assignee_id: null });
const editing = ref(false);

function startEdit() {
  if (!attrs.value) return;
  editBuffer.value = {
    location: attrs.value.location ?? "",
    description: attrs.value.description ?? "",
    assignee_id: attrs.value.assignee_id ?? null
  };
  editing.value = true;
}

async function saveEdit() {
  try {
    const res = await updateIncident(incidentId.value, editBuffer.value);
    incident.value = res;
    editing.value = false;
    message.success("Saved");
  } catch (e) {
    message.error(`Save failed: ${(e as ApiError).message}`);
  }
}

const assigneeOptions = computed(() =>
  orgUsers.value.map((u) => ({
    label: `${u.name} (${u.role})`,
    value: Number(u.id)
  }))
);

// ---- comments / witnesses --------------------------------------------------

const newComment = ref("");
async function postComment() {
  if (!newComment.value.trim()) return;
  try {
    await addComment(incidentId.value, newComment.value);
    newComment.value = "";
    await loadAux();
  } catch (e) {
    message.error(`Comment failed: ${(e as ApiError).message}`);
  }
}

const newWitness = ref({ name: "", email: "", phone: "", statement: "" });
async function postWitness() {
  if (!newWitness.value.name.trim()) return;
  try {
    await addWitness(incidentId.value, {
      name: newWitness.value.name,
      email: newWitness.value.email || undefined,
      phone: newWitness.value.phone || undefined,
      statement: newWitness.value.statement || undefined
    });
    newWitness.value = { name: "", email: "", phone: "", statement: "" };
    await loadAux();
  } catch (e) {
    message.error(`Witness failed: ${(e as ApiError).message}`);
  }
}

// ---- photo upload ----------------------------------------------------------

async function onUpload({ file }: { file: { file?: File | null } }) {
  if (!file.file) return;
  try {
    await uploadAttachment(incidentId.value, file.file);
    message.success("Uploaded");
    await loadAux();
  } catch (e) {
    message.error(`Upload failed: ${(e as ApiError).message}`);
  }
}

// ---- corrective actions ----------------------------------------------------

const newAction = ref({
  title: "",
  description: "",
  note: "",
  due_date: Date.now() + 7 * 24 * 3600_000,
  assignee_id: null as number | null
});
const showActionForm = ref(false);

async function postAction() {
  if (!newAction.value.title || !newAction.value.assignee_id) {
    message.error("Title and assignee are required");
    return;
  }
  try {
    await createIncidentAction(incidentId.value, {
      title: newAction.value.title,
      description: newAction.value.description,
      note: newAction.value.note || undefined,
      due_date: new Date(newAction.value.due_date).toISOString(),
      assignee_id: newAction.value.assignee_id
    });
    newAction.value = {
      title: "",
      description: "",
      note: "",
      due_date: Date.now() + 7 * 24 * 3600_000,
      assignee_id: null
    };
    showActionForm.value = false;
    await loadAux();
  } catch (e) {
    message.error(`Action failed: ${(e as ApiError).message}`);
  }
}

// ---- transition dialog ------------------------------------------------------
//
// Every transition opens this dialog so the operator can attach an optional
// note before the state change fires. Confirming POSTs to /transitions with
// { event, note }.
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
}>({
  show: false,
  actionId: null,
  event: null,
  note: ""
});

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
    message.success(`Action: ${event}`);
    // Verifying the last corrective action auto-closes the parent incident on
    // the backend, so we have to reload both views (loadAux alone misses it).
    await Promise.all([ loadIncident(), loadAux() ]);
  } catch (e) {
    message.error(`Action transition failed: ${(e as ApiError).message}`);
  }
}

function allowedForAction(
  action_state: CorrectiveActionAttributes["state"],
  assignee_id: number | undefined
) {
  if (!auth.user) return [];
  const isMine = String(assignee_id) === auth.user.id;
  return allowedActionTransitions(action_state, auth.user.role, isMine);
}

// ---- corrective-action activity feed ---------------------------------------

interface ActionEventRow {
  id: string;
  event_name: CorrectiveActionEventAttributes["event_name"];
  note: string | null;
  actor_id: number;
  created_at: string;
}

const actionEvents = ref<Record<string, ActionEventRow[]>>({});
const actionEventsLoading = ref<Record<string, boolean>>({});
const actionShowActivity = ref<Record<string, boolean>>({});

async function toggleActivity(actionId: string) {
  const isOpen = actionShowActivity.value[actionId] === true;
  if (isOpen) {
    actionShowActivity.value = { ...actionShowActivity.value, [actionId]: false };
    return;
  }
  actionShowActivity.value = { ...actionShowActivity.value, [actionId]: true };
  await loadActionEvents(actionId);
}

async function loadActionEvents(actionId: string) {
  actionEventsLoading.value = { ...actionEventsLoading.value, [actionId]: true };
  try {
    const res = await listActionEvents(actionId);
    actionEvents.value = {
      ...actionEvents.value,
      [actionId]: res.data.map((r) => ({
        id: r.id,
        event_name: r.attributes.event_name,
        note: r.attributes.note,
        actor_id: r.attributes.actor_id,
        created_at: r.attributes.created_at
      }))
    };
  } catch (e) {
    message.error(`Could not load activity: ${(e as ApiError).message}`);
  } finally {
    actionEventsLoading.value = { ...actionEventsLoading.value, [actionId]: false };
  }
}

const ACTION_EVENT_LABELS: Record<CorrectiveActionEventAttributes["event_name"], string> = {
  assigned:  "assigned",
  started:   "started",
  completed: "marked as done",
  verified:  "verified",
  cancelled: "cancelled"
};

function eventTimelineType(name: CorrectiveActionEventAttributes["event_name"]) {
  switch (name) {
    case "assigned":  return "info";
    case "started":   return "default";
    case "completed": return "success";
    case "verified":  return "success";
    case "cancelled": return "error";
    default:          return "default";
  }
}

function eventTimelineTitle(evt: ActionEventRow) {
  const actor = orgUsers.value.find((u) => Number(u.id) === evt.actor_id);
  const who = actor?.name ?? `User #${evt.actor_id}`;
  return `${who} ${ACTION_EVENT_LABELS[evt.event_name]}`;
}

// ---- versions / audit trail rendering --------------------------------------
//
// PaperTrail emits changeset as `{ field: [old, new] }`. We render the diff
// as human-readable rows; the JSON dump is hidden behind a toggle for the
// rare moments when raw inspection is needed.
const VERSION_EVENT_LABEL: Record<string, string> = {
  create: "Created",
  update: "Updated",
  destroy: "Deleted"
};
function versionTitle(v: { attrs: VersionAttributes }): string {
  const evt = VERSION_EVENT_LABEL[v.attrs.event] ?? v.attrs.event;
  const who = v.attrs.whodunnit_user?.name ?? "system";
  return `${evt} · ${who}`;
}

const VERSION_FIELD_LABEL: Record<string, string> = {
  state: "State",
  severity: "Severity",
  incident_type: "Type",
  occurred_at: "Occurred at",
  location: "Location",
  summary: "Summary",
  description: "Description",
  root_cause: "Root cause",
  submitted_at: "Submitted at",
  triaged_at: "Triaged at",
  closed_at: "Closed at",
  sla_breached_at: "SLA breached at",
  reporter_id: "Reporter",
  assignee_id: "Assignee",
  site_id: "Site",
  organization_id: "Organization"
};
const VERSION_HIDDEN_FIELDS = new Set(["created_at", "updated_at", "id"]);

function formatVersionValue(field: string, value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (field === "severity" && typeof value === "number") {
    return `S${value} — ${severityLabel(value)}`;
  }
  if (field.endsWith("_at") && typeof value === "string") {
    return fmtDate(value);
  }
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}

interface VersionRow {
  field: string;
  label: string;
  from: string;
  to: string;
  isCreate: boolean;
}
function versionRows(v: { attrs: VersionAttributes }): VersionRow[] {
  const isCreate = v.attrs.event === "create";
  return Object.entries(v.attrs.changes ?? {})
    .filter(([k]) => !VERSION_HIDDEN_FIELDS.has(k))
    .map(([k, pair]) => {
      const [fromRaw, toRaw] = Array.isArray(pair) ? pair : [null, pair];
      return {
        field: k,
        label: VERSION_FIELD_LABEL[k] ?? k,
        from: formatVersionValue(k, fromRaw),
        to: formatVersionValue(k, toRaw),
        isCreate
      };
    })
    .filter((row) => row.from !== row.to);
}
</script>

<template>
  <n-space
    vertical
    :size="16"
  >
    <n-button
      quaternary
      @click="router.push('/incidents')"
    >
      ← Back to list
    </n-button>

    <n-spin :show="loading">
      <template v-if="attrs">
        <n-card>
          <n-space
            justify="space-between"
            align="center"
            :wrap="true"
          >
            <n-space
              align="center"
              :size="12"
              :wrap="true"
            >
              <h2 style="margin:0">
                #{{ incidentId }} · {{ attrs.summary }}
              </h2>
              <n-tag
                :type="stateTagType(attrs.state)"
                :bordered="false"
              >
                {{ attrs.state }}
              </n-tag>
              <span
                :style="{
                  display: 'inline-block',
                  padding: '2px 10px',
                  borderRadius: '12px',
                  color: '#fff',
                  background: severityColor(attrs.severity),
                  fontSize: '12px'
                }"
              >S{{ attrs.severity }}</span>
              <n-tag
                v-if="attrs.triage_overdue"
                type="error"
                :bordered="false"
              >
                triage overdue
              </n-tag>
            </n-space>
            <n-space>
              <n-popconfirm
                v-for="t in transitions"
                :key="t"
                @positive-click="doTransition(t)"
              >
                <template #trigger>
                  <n-button
                    size="small"
                    :type="t === 'reject' ? 'error' : 'primary'"
                  >
                    {{ transitionLabel[t] }}
                  </n-button>
                </template>
                Confirm: {{ transitionLabel[t] }}?
              </n-popconfirm>
            </n-space>
          </n-space>
        </n-card>

        <n-card>
          <n-tabs
            v-model:value="tab"
            type="line"
          >
            <!-- Details ---------------------------------------------------- -->
            <n-tab-pane
              name="details"
              tab="Details"
            >
              <n-space
                v-if="editable && !editing"
                justify="end"
              >
                <n-button
                  size="small"
                  @click="startEdit"
                >
                  Edit
                </n-button>
              </n-space>

              <n-descriptions
                v-if="!editing"
                :column="2"
                bordered
                label-placement="left"
                style="margin-top:8px"
              >
                <n-descriptions-item label="Type">
                  {{ attrs.incident_type }}
                </n-descriptions-item>
                <n-descriptions-item label="Site">
                  {{ site?.attributes.name ?? attrs.site_id }}
                </n-descriptions-item>
                <n-descriptions-item label="Location">
                  {{ attrs.location }}
                </n-descriptions-item>
                <n-descriptions-item label="Occurred">
                  {{ fmtDate(attrs.occurred_at) }}
                </n-descriptions-item>
                <n-descriptions-item label="Reporter">
                  {{ reporter?.attributes.name ?? attrs.reporter_id }}
                </n-descriptions-item>
                <n-descriptions-item label="Assignee">
                  {{ assignee?.attributes.name ?? "—" }}
                </n-descriptions-item>
                <n-descriptions-item label="Triage deadline">
                  {{ fmtDate(attrs.triage_deadline) }}
                </n-descriptions-item>
                <n-descriptions-item label="Submitted at">
                  {{ fmtDate(attrs.submitted_at) }}
                </n-descriptions-item>
                <n-descriptions-item
                  label="Description"
                  :span="2"
                >
                  {{ attrs.description }}
                </n-descriptions-item>
              </n-descriptions>

              <n-form v-else>
                <n-form-item label="Location">
                  <n-input v-model:value="editBuffer.location" />
                </n-form-item>
                <n-form-item label="Description">
                  <n-input
                    v-model:value="editBuffer.description"
                    type="textarea"
                    :autosize="{ minRows: 3 }"
                  />
                </n-form-item>
                <n-form-item
                  v-if="auth.user?.role !== 'worker'"
                  label="Assignee"
                >
                  <n-select
                    v-model:value="editBuffer.assignee_id"
                    :options="assigneeOptions"
                    clearable
                    placeholder="Select assignee"
                  />
                </n-form-item>
                <n-space>
                  <n-button @click="editing = false">
                    Cancel
                  </n-button>
                  <n-button
                    type="primary"
                    @click="saveEdit"
                  >
                    Save
                  </n-button>
                </n-space>
              </n-form>

              <h3 style="margin-top:24px">
                Photos
              </h3>
              <n-upload
                :default-upload="false"
                accept="image/*"
                :show-file-list="false"
                @change="onUpload"
              >
                <n-button size="small">
                  Upload photo
                </n-button>
              </n-upload>
              <n-image-group
                v-if="attachments.length"
                style="margin-top:12px"
              >
                <n-space>
                  <n-image
                    v-for="a in attachments"
                    :key="a.id"
                    :src="absoluteApiUrl(a.attrs.url)"
                    width="120"
                    height="120"
                    object-fit="cover"
                  />
                </n-space>
              </n-image-group>
              <n-empty
                v-else
                description="No photos yet"
              />
            </n-tab-pane>

            <!-- Witnesses -------------------------------------------------- -->
            <n-tab-pane
              name="witnesses"
              tab="Witnesses"
            >
              <n-list bordered>
                <n-list-item
                  v-for="w in witnesses"
                  :key="w.id"
                >
                  <n-thing
                    :title="w.attrs.name"
                    :description="w.attrs.email || w.attrs.phone || '—'"
                  >
                    {{ w.attrs.statement }}
                  </n-thing>
                </n-list-item>
                <n-list-item v-if="!witnesses.length">
                  <n-empty description="No witnesses" />
                </n-list-item>
              </n-list>
              <n-card
                title="Add witness"
                style="margin-top:16px"
              >
                <n-form>
                  <n-form-item label="Name">
                    <n-input v-model:value="newWitness.name" />
                  </n-form-item>
                  <n-form-item label="Email">
                    <n-input v-model:value="newWitness.email" />
                  </n-form-item>
                  <n-form-item label="Phone">
                    <n-input v-model:value="newWitness.phone" />
                  </n-form-item>
                  <n-form-item label="Statement">
                    <n-input
                      v-model:value="newWitness.statement"
                      type="textarea"
                      :autosize="{ minRows: 2 }"
                    />
                  </n-form-item>
                  <n-button
                    type="primary"
                    @click="postWitness"
                  >
                    Add
                  </n-button>
                </n-form>
              </n-card>
            </n-tab-pane>

            <!-- Comments --------------------------------------------------- -->
            <n-tab-pane
              name="comments"
              tab="Comments"
            >
              <n-list bordered>
                <n-list-item
                  v-for="c in comments"
                  :key="c.id"
                >
                  <n-thing
                    :title="c.author ?? `User ${c.attrs.author_id}`"
                    :description="fmtRelative(c.attrs.created_at)"
                  >
                    {{ c.attrs.body }}
                  </n-thing>
                </n-list-item>
                <n-list-item v-if="!comments.length">
                  <n-empty description="No comments yet" />
                </n-list-item>
              </n-list>
              <n-space
                style="margin-top:12px"
                align="start"
              >
                <n-input
                  v-model:value="newComment"
                  type="textarea"
                  :autosize="{ minRows: 2 }"
                  placeholder="Write a comment…"
                  style="width: 480px"
                />
                <n-button
                  type="primary"
                  @click="postComment"
                >
                  Post
                </n-button>
              </n-space>
            </n-tab-pane>

            <!-- Corrective actions ---------------------------------------- -->
            <n-tab-pane
              name="actions"
              tab="Corrective Actions"
            >
              <n-space justify="end">
                <n-button
                  v-if="auth.user?.role !== 'worker'"
                  size="small"
                  @click="showActionForm = !showActionForm"
                >
                  {{ showActionForm ? "Cancel" : "+ New action" }}
                </n-button>
              </n-space>

              <n-card
                v-if="showActionForm"
                style="margin: 8px 0"
                title="New corrective action"
              >
                <n-form>
                  <n-form-item label="Title">
                    <n-input v-model:value="newAction.title" />
                  </n-form-item>
                  <n-form-item label="Description">
                    <n-input
                      v-model:value="newAction.description"
                      type="textarea"
                      :autosize="{ minRows: 2 }"
                    />
                  </n-form-item>
                  <n-form-item label="Note for assignee (optional)">
                    <n-input
                      v-model:value="newAction.note"
                      type="textarea"
                      :autosize="{ minRows: 2, maxRows: 4 }"
                      placeholder="Why are you assigning this now? Context for the worker."
                    />
                  </n-form-item>
                  <n-form-item label="Due date">
                    <n-date-picker
                      v-model:value="newAction.due_date"
                      type="datetime"
                    />
                  </n-form-item>
                  <n-form-item label="Assignee">
                    <n-select
                      v-model:value="newAction.assignee_id"
                      :options="assigneeOptions"
                      placeholder="Select assignee"
                    />
                  </n-form-item>
                  <n-button
                    type="primary"
                    @click="postAction"
                  >
                    Create
                  </n-button>
                </n-form>
              </n-card>

              <n-list bordered>
                <n-list-item
                  v-for="a in actions"
                  :key="a.id"
                >
                  <n-thing
                    :title="a.attrs.title"
                    :description="a.attrs.description"
                  >
                    <template #header-extra>
                      <n-space>
                        <n-tag
                          :type="actionStateTagType(a.attrs.state)"
                          :bordered="false"
                        >
                          {{ a.attrs.state }}
                        </n-tag>
                        <n-tag
                          v-if="a.attrs.overdue"
                          type="error"
                          :bordered="false"
                        >
                          overdue
                        </n-tag>
                      </n-space>
                    </template>
                    <p style="color:#666; margin: 4px 0">
                      Due {{ fmtDate(a.attrs.due_date) }}
                    </p>
                    <n-space>
                      <n-button
                        v-for="ev in allowedForAction(a.attrs.state, a.attrs.assignee_id)"
                        :key="ev"
                        size="small"
                        @click="openTransitionDialog(a.id, ev)"
                      >
                        {{ ev }}
                      </n-button>
                      <n-button
                        size="small"
                        text
                        @click="toggleActivity(a.id)"
                      >
                        {{ actionShowActivity[a.id] ? "Hide activity" : "Show activity" }}
                      </n-button>
                    </n-space>

                    <div
                      v-if="actionShowActivity[a.id]"
                      style="margin-top: 12px"
                    >
                      <n-spin :show="actionEventsLoading[a.id] === true">
                        <n-empty
                          v-if="(actionEvents[a.id]?.length ?? 0) === 0 && actionEventsLoading[a.id] !== true"
                          description="No activity yet"
                          size="small"
                        />
                        <n-timeline v-else>
                          <n-timeline-item
                            v-for="evt in actionEvents[a.id] ?? []"
                            :key="evt.id"
                            :type="eventTimelineType(evt.event_name)"
                            :title="eventTimelineTitle(evt)"
                            :content="evt.note ?? ''"
                            :time="fmtDate(evt.created_at)"
                          />
                        </n-timeline>
                      </n-spin>
                    </div>
                  </n-thing>
                </n-list-item>
                <n-list-item v-if="!actions.length">
                  <n-empty description="No corrective actions" />
                </n-list-item>
              </n-list>
            </n-tab-pane>

            <!-- Activity log ----------------------------------------------- -->
            <n-tab-pane
              name="versions"
              tab="Log"
            >
              <n-list bordered>
                <n-list-item
                  v-for="v in versions"
                  :key="v.id"
                >
                  <n-thing
                    :title="versionTitle(v)"
                    :description="fmtDate(v.attrs.created_at)"
                  >
                    <div
                      v-if="versionRows(v).length"
                      class="version-diff"
                    >
                      <div
                        v-for="row in versionRows(v)"
                        :key="row.field"
                        class="version-row"
                      >
                        <span class="version-field">{{ row.label }}</span>
                        <template v-if="row.isCreate">
                          <span class="version-value-new">{{ row.to }}</span>
                        </template>
                        <template v-else>
                          <span class="version-value-old">{{ row.from }}</span>
                          <span class="version-arrow">→</span>
                          <span class="version-value-new">{{ row.to }}</span>
                        </template>
                      </div>
                    </div>
                    <div
                      v-else
                      style="font-size:12px; color:#999"
                    >
                      No tracked field changes.
                    </div>
                  </n-thing>
                </n-list-item>
                <n-list-item v-if="!versions.length">
                  <n-empty description="No history yet" />
                </n-list-item>
              </n-list>
            </n-tab-pane>
          </n-tabs>
        </n-card>
      </template>
    </n-spin>

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

<style scoped>
.version-diff {
  display: flex;
  flex-direction: column;
  gap: 4px;
  margin-top: 4px;
  font-size: 13px;
}
.version-row {
  display: flex;
  align-items: baseline;
  gap: 8px;
  flex-wrap: wrap;
}
.version-field {
  flex: 0 0 140px;
  color: #666;
  font-weight: 500;
}
.version-value-old {
  color: #999;
  text-decoration: line-through;
}
.version-arrow {
  color: #999;
}
.version-value-new {
  color: #1f2937;
}
</style>
