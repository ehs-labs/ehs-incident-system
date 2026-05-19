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
import { transitionAction } from "@/api/actions";
import { listOrgUsers } from "@/api/admin";
import { useAuthStore } from "@/stores/auth";
import { findIncluded } from "@/utils/jsonapi";
import {
  fmtDate,
  fmtRelative,
  severityColor,
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
    const res = await listOrgUsers();
    orgUsers.value = res.data.map((r) => ({
      id: r.id,
      name: r.attributes.name ?? "",
      email: r.attributes.email ?? "",
      role: r.attributes.role ?? "worker"
    }));
  } catch {
    /* fine — pickers fall back to read-only */
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
      due_date: new Date(newAction.value.due_date).toISOString(),
      assignee_id: newAction.value.assignee_id
    });
    newAction.value = {
      title: "",
      description: "",
      due_date: Date.now() + 7 * 24 * 3600_000,
      assignee_id: null
    };
    showActionForm.value = false;
    await loadAux();
  } catch (e) {
    message.error(`Action failed: ${(e as ApiError).message}`);
  }
}

async function actionTransition(
  actionId: string,
  event: "start" | "complete" | "verify"
) {
  try {
    await transitionAction(actionId, event);
    message.success(`Action: ${event}`);
    // Reload the incident itself too: verifying the last corrective action
    // triggers maybe_close_parent_incident! on the backend, which auto-closes
    // the incident. loadAux() alone does not refresh incident.value.
    await Promise.all([loadIncident(), loadAux()]);
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
                        @click="actionTransition(a.id, ev)"
                      >
                        {{ ev }}
                      </n-button>
                    </n-space>
                  </n-thing>
                </n-list-item>
                <n-list-item v-if="!actions.length">
                  <n-empty description="No corrective actions" />
                </n-list-item>
              </n-list>
            </n-tab-pane>

            <!-- Versions --------------------------------------------------- -->
            <n-tab-pane
              name="versions"
              tab="Versions"
            >
              <n-list bordered>
                <n-list-item
                  v-for="v in versions"
                  :key="v.id"
                >
                  <n-thing
                    :title="`${v.attrs.event} · ${v.attrs.whodunnit_user?.name ?? 'system'}`"
                    :description="fmtDate(v.attrs.created_at)"
                  >
                    <pre style="font-size:12px; white-space:pre-wrap; margin:0">{{
                      JSON.stringify(v.attrs.changes, null, 2)
                    }}</pre>
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
  </n-space>
</template>
