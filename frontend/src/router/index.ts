import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router";
import { useAuthStore } from "@/stores/auth";

const routes: RouteRecordRaw[] = [
  { path: "/login",  component: () => import("@/views/Login.vue"),  meta: { public: true } },
  { path: "/signup", component: () => import("@/views/Signup.vue"), meta: { public: true } },
  { path: "/password/reset", component: () => import("@/views/PasswordReset.vue"), meta: { public: true } },

  // Authenticated area
  {
    path: "/",
    component: () => import("@/layouts/AppShell.vue"),
    children: [
      { path: "",                          redirect: "/dashboard" },
      { path: "dashboard",                 component: () => import("@/views/Dashboard.vue") },
      { path: "incidents",                 component: () => import("@/views/Incidents.vue") },
      { path: "incidents/new",             component: () => import("@/views/IncidentNew.vue") },
      { path: "incidents/:id",             component: () => import("@/views/IncidentDetail.vue") },
      { path: "actions",                   component: () => import("@/views/Actions.vue") },
      { path: "inbox",                     component: () => import("@/views/Inbox.vue") },
      { path: "profile",                   component: () => import("@/views/admin/Profile.vue") },

      // Admin
      { path: "admin/users",               component: () => import("@/views/admin/UserList.vue"),  meta: { roles: ["admin"] } },
      { path: "admin/users/invite",        component: () => import("@/views/admin/UserInvite.vue"), meta: { roles: ["admin"] } },
      { path: "admin/users/:id",           component: () => import("@/views/admin/UserEdit.vue"),  meta: { roles: ["admin"] } },
      { path: "admin/sites",               component: () => import("@/views/admin/SiteList.vue"),  meta: { roles: ["admin"] } },
      { path: "admin/settings",            component: () => import("@/views/admin/Settings.vue"),  meta: { roles: ["admin"] } }
    ]
  },

  { path: "/:pathMatch(.*)*", component: () => import("@/views/NotFound.vue"), meta: { public: true } }
];

export const router = createRouter({
  history: createWebHistory(),
  routes
});

router.beforeEach(async (to) => {
  if (to.meta.public) return true;

  const auth = useAuthStore();
  if (!auth.isAuthenticated) {
    await auth.tryRefresh();
    if (!auth.isAuthenticated) return { path: "/login", query: { next: to.fullPath } };
  }

  const allowedRoles = to.meta.roles as string[] | undefined;
  if (allowedRoles && !allowedRoles.includes(auth.user?.role ?? "")) {
    return { path: "/dashboard" };
  }

  return true;
});
