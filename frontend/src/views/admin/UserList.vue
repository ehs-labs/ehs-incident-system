<script setup lang="ts">
import { h, onMounted, ref } from "vue";
import { useRouter, RouterLink } from "vue-router";
import {
  NDataTable,
  NSpace,
  NButton,
  NTag,
  NCard,
  NPopconfirm,
  useMessage,
  type DataTableColumns
} from "naive-ui";
import {
  listOrgUsers,
  lockUser,
  unlockUser,
  deleteUser
} from "@/api/admin";
import type { User, ApiError } from "@/types/api";

const message = useMessage();
const router = useRouter();
const rows = ref<(User & { id: string })[]>([]);
const loading = ref(true);

async function load() {
  loading.value = true;
  try {
    const res = await listOrgUsers();
    rows.value = res.data.map((r) => ({ ...r.attributes, id: r.id }));
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed");
  } finally {
    loading.value = false;
  }
}

async function toggleLock(u: User & { id: string }) {
  try {
    if (u.locked) await unlockUser(u.id);
    else await lockUser(u.id);
    message.success("Updated");
    await load();
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed");
  }
}

async function remove(id: string) {
  try {
    await deleteUser(id);
    message.success("Deleted");
    await load();
  } catch (e) {
    message.error((e as ApiError).message ?? "Failed");
  }
}

onMounted(load);

const columns: DataTableColumns<User & { id: string }> = [
  { title: "Email", key: "email" },
  { title: "Name", key: "name" },
  {
    title: "Role",
    key: "role",
    render: (r) => h(NTag, { bordered: false }, () => r.role)
  },
  {
    title: "Locked",
    key: "locked",
    render: (r) =>
      r.locked
        ? h(NTag, { type: "error", bordered: false }, () => "locked")
        : h("span", { style: "color:#888" }, "—")
  },
  {
    title: "Actions",
    key: "x",
    render: (r) =>
      h(NSpace, {}, () => [
        h(
          NButton,
          { size: "small", onClick: () => router.push(`/admin/users/${r.id}`) },
          () => "Edit"
        ),
        h(
          NButton,
          { size: "small", onClick: () => toggleLock(r) },
          () => (r.locked ? "Unlock" : "Lock")
        ),
        h(
          NPopconfirm,
          { onPositiveClick: () => remove(r.id) },
          {
            trigger: () =>
              h(NButton, { size: "small", type: "error" }, () => "Delete"),
            default: () => "Delete this user?"
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
        Users
      </h1>
      <RouterLink to="/admin/users/invite">
        <n-button type="primary">
          + Invite user
        </n-button>
      </RouterLink>
    </n-space>
    <n-card>
      <n-data-table
        :columns="columns"
        :data="rows"
        :loading="loading"
        :bordered="false"
      />
    </n-card>
  </n-space>
</template>
