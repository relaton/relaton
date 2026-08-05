import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  test: {
    // Per-file override via `// @vitest-environment happy-dom` where DOM is
    // needed; pure logic tests stay in the default node environment.
    environment: "node",
  },
});
