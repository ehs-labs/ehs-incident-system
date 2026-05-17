import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import path from "node:path";

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") }
  },
  server: {
    host: true,
    port: 5173,
    proxy: {
      // Optional dev convenience: proxy /api to core-api on host:3000
      "/api": {
        target: "http://localhost:3000",
        changeOrigin: true
      }
    }
  },
  test: {
    globals: true,
    environment: "happy-dom",
    // Vitest only runs unit specs. Playwright e2e specs live under tests/e2e/
    // and use `@playwright/test`'s test runner — exclude them here so vitest
    // doesn't try to evaluate them.
    include: ["tests/unit/**/*.spec.ts", "src/**/*.spec.ts"],
    exclude: ["tests/e2e/**", "node_modules/**"],
    coverage: {
      reporter: ["text", "html"]
    }
  }
});
