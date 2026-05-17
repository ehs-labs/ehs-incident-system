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
    coverage: {
      reporter: ["text", "html"]
    }
  }
});
