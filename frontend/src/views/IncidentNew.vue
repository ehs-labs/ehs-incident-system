<script setup lang="ts">
import { ref, computed, reactive } from "vue";
import { useRouter } from "vue-router";
import {
  NSteps,
  NStep,
  NCard,
  NForm,
  NFormItem,
  NInput,
  NSelect,
  NDatePicker,
  NButton,
  NSpace,
  NUpload,
  NDynamicInput,
  NAlert,
  useMessage,
  type UploadFileInfo
} from "naive-ui";
import { useAuthStore } from "@/stores/auth";
import {
  createIncident,
  transitionIncident,
  uploadAttachment,
  addWitness
} from "@/api/incidents";
import { ApiError, fieldFromPointer, type IncidentType, type ProblemError, type Severity } from "@/types/api";

const router = useRouter();
const auth = useAuthStore();
const message = useMessage();

const step = ref(0);
const submitting = ref(false);
const createdIncidentId = ref<string | null>(null);
const error = ref<string | null>(null);
// Field-level errors from the most recent failed request, mapped from
// RFC 7807 `errors[]` rows. Cleared on every new attempt.
const fieldErrors = ref<ProblemError[]>([]);

function applyApiError(e: unknown) {
  const api = e as ApiError;
  error.value = api.problem?.detail ?? api.message;
  fieldErrors.value = api.problem?.errors ?? [];
}

// Mirrors Incident::VALID_TYPES on the backend; keep in sync.
const typeOptions: { label: string; value: IncidentType }[] = [
  { label: "Collision",              value: "collision" },
  { label: "Slip",                   value: "slip" },
  { label: "Fall",                   value: "fall" },
  { label: "Near-miss",              value: "near_miss" },
  { label: "Chemical exposure",      value: "exposure" },
  { label: "Mechanical failure",     value: "mechanical" },
  { label: "Electrical incident",    value: "electrical" },
  { label: "Fire",                   value: "fire" },
  { label: "Other",                  value: "other" }
];

const severityOptions = [1, 2, 3, 4, 5].map((s) => ({
  label: `S${s}`,
  value: s as Severity
}));

const siteOptions = computed(() =>
  auth.sites.map((s) => ({ label: s.name, value: Number(s.id) }))
);

interface WitnessDraft {
  name: string;
  email: string;
  phone: string;
  statement: string;
}

const form = reactive({
  incident_type: "slip" as IncidentType,
  severity: 3 as Severity,
  summary: "",
  description: "",
  site_id: (siteOptions.value[0]?.value ?? null) as number | null,
  location: "",
  occurred_at: Date.now()
});

const witnesses = ref<WitnessDraft[]>([]);
const files = ref<UploadFileInfo[]>([]);

function makeWitness(): WitnessDraft {
  return { name: "", email: "", phone: "", statement: "" };
}

const canAdvance = computed(() => {
  if (step.value === 0)
    return !!form.summary && !!form.incident_type && !!form.severity;
  if (step.value === 1) return !!form.site_id && !!form.location && !!form.occurred_at;
  return true;
});

function next() {
  if (canAdvance.value) step.value = Math.min(step.value + 1, 4);
}
function prev() {
  step.value = Math.max(step.value - 1, 0);
}

async function persistIncident(): Promise<string | null> {
  if (createdIncidentId.value) return createdIncidentId.value;
  if (!form.site_id) {
    error.value = "Site is required";
    return null;
  }
  try {
    const res = await createIncident({
      incident_type: form.incident_type,
      severity: form.severity,
      summary: form.summary,
      description: form.description,
      site_id: form.site_id,
      location: form.location,
      occurred_at: new Date(form.occurred_at).toISOString()
    });
    createdIncidentId.value = res.data.id;
    return res.data.id;
  } catch (e) {
    applyApiError(e);
    return null;
  }
}

async function saveDraft() {
  submitting.value = true;
  error.value = null; fieldErrors.value = [];
  try {
    const id = await persistIncident();
    if (!id) return;
    await uploadAttached(id);
    await saveWitnesses(id);
    message.success("Draft saved");
    router.push(`/incidents/${id}`);
  } finally {
    submitting.value = false;
  }
}

async function uploadAttached(id: string) {
  for (const f of files.value) {
    if (f.file) {
      await uploadAttachment(id, f.file as File);
    }
  }
}

async function saveWitnesses(id: string) {
  for (const w of witnesses.value) {
    if (w.name)
      await addWitness(id, {
        name: w.name,
        email: w.email || undefined,
        phone: w.phone || undefined,
        statement: w.statement || undefined
      });
  }
}

async function finalSubmit() {
  submitting.value = true;
  error.value = null; fieldErrors.value = [];
  try {
    const id = await persistIncident();
    if (!id) return;
    await uploadAttached(id);
    await saveWitnesses(id);
    await transitionIncident(id, "submit");
    message.success("Incident submitted");
    router.push(`/incidents/${id}`);
  } catch (e) {
    applyApiError(e);
  } finally {
    submitting.value = false;
  }
}

function onFileChange({ fileList }: { fileList: UploadFileInfo[] }) {
  files.value = fileList;
}
</script>

<template>
  <n-space
    vertical
    :size="16"
  >
    <h1 style="margin:0">
      Report an incident
    </h1>

    <n-alert
      v-if="error"
      type="error"
      closable
      @close="error = null; fieldErrors = [];"
    >
      <div>{{ error }}</div>
      <ul
        v-if="fieldErrors.length"
        style="margin: 6px 0 0 1.25em; padding: 0;"
      >
        <li
          v-for="(fe, i) in fieldErrors"
          :key="i"
        >
          <strong>{{ fieldFromPointer(fe.pointer) ?? fe.parameter ?? 'field' }}</strong>: {{ fe.detail }}
        </li>
      </ul>
    </n-alert>

    <n-card>
      <n-steps
        :current="step + 1"
        size="small"
      >
        <n-step title="What" />
        <n-step title="Where & when" />
        <n-step title="Witnesses" />
        <n-step title="Photos" />
        <n-step title="Submit" />
      </n-steps>
    </n-card>

    <n-card>
      <!-- Step 1: What -->
      <template v-if="step === 0">
        <n-form>
          <n-form-item label="Incident type">
            <n-select
              v-model:value="form.incident_type"
              :options="typeOptions"
            />
          </n-form-item>
          <n-form-item label="Severity">
            <n-select
              v-model:value="form.severity"
              :options="severityOptions"
            />
          </n-form-item>
          <n-form-item label="Summary">
            <n-input
              v-model:value="form.summary"
              placeholder="One-line summary"
              maxlength="120"
              show-count
            />
          </n-form-item>
          <n-form-item label="Description">
            <n-input
              v-model:value="form.description"
              type="textarea"
              :autosize="{ minRows: 3, maxRows: 8 }"
              placeholder="What happened?"
            />
          </n-form-item>
        </n-form>
      </template>

      <!-- Step 2: Where & when -->
      <template v-else-if="step === 1">
        <n-form>
          <n-form-item label="Site">
            <n-select
              v-model:value="form.site_id"
              :options="siteOptions"
              :disabled="siteOptions.length === 0"
              :placeholder="siteOptions.length === 0 ? 'No sites available' : 'Select a site'"
            />
          </n-form-item>
          <n-form-item label="Location">
            <n-input
              v-model:value="form.location"
              placeholder="e.g. Aisle 5, Loading bay"
            />
          </n-form-item>
          <n-form-item label="Occurred at">
            <n-date-picker
              v-model:value="form.occurred_at"
              type="datetime"
              clearable
            />
          </n-form-item>
        </n-form>
      </template>

      <!-- Step 3: Witnesses -->
      <template v-else-if="step === 2">
        <p style="color:#666">
          Optional. Add anyone who saw what happened.
        </p>
        <n-dynamic-input
          v-model:value="witnesses"
          :on-create="makeWitness"
          #="{ value }"
        >
          <n-space
            vertical
            style="width:100%"
          >
            <n-input
              v-model:value="value.name"
              placeholder="Name"
            />
            <n-input
              v-model:value="value.email"
              placeholder="Email"
            />
            <n-input
              v-model:value="value.phone"
              placeholder="Phone"
            />
            <n-input
              v-model:value="value.statement"
              type="textarea"
              placeholder="Statement (optional)"
              :autosize="{ minRows: 2 }"
            />
          </n-space>
        </n-dynamic-input>
      </template>

      <!-- Step 4: Photos -->
      <template v-else-if="step === 3">
        <p style="color:#666">
          Add photos of the scene. They upload when you save or submit.
        </p>
        <n-upload
          multiple
          :default-upload="false"
          list-type="image-card"
          accept="image/*"
          :file-list="files"
          @change="onFileChange"
        >
          Click or drag to upload
        </n-upload>
      </template>

      <!-- Step 5: Review/submit -->
      <template v-else-if="step === 4">
        <h3>Review</h3>
        <p><strong>Type:</strong> {{ form.incident_type }} · <strong>Severity:</strong> S{{ form.severity }}</p>
        <p><strong>Summary:</strong> {{ form.summary }}</p>
        <p><strong>Location:</strong> {{ form.location }}</p>
        <p><strong>Description:</strong> {{ form.description || "—" }}</p>
        <p><strong>Witnesses:</strong> {{ witnesses.length }}</p>
        <p><strong>Photos:</strong> {{ files.length }}</p>
      </template>

      <n-space
        justify="space-between"
        style="margin-top: 24px"
      >
        <n-button
          :disabled="step === 0 || submitting"
          @click="prev"
        >
          Back
        </n-button>
        <n-space>
          <n-button
            :loading="submitting"
            @click="saveDraft"
          >
            Save draft
          </n-button>
          <n-button
            v-if="step < 4"
            type="primary"
            :disabled="!canAdvance || submitting"
            @click="next"
          >
            Next
          </n-button>
          <n-button
            v-else
            type="primary"
            :loading="submitting"
            @click="finalSubmit"
          >
            Submit incident
          </n-button>
        </n-space>
      </n-space>
    </n-card>
  </n-space>
</template>
