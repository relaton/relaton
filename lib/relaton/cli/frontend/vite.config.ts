import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "node:path";

const root = import.meta.dirname;

// Library-mode build that emits exactly ONE self-executing bundle
// (`dist/app.iife.js`) plus one stylesheet (`dist/style.css`). Vue and
// Tailwind are bundled in, so the output is fully self-contained and can be
// inlined verbatim into a generated HTML page by the relaton-cli generator.
//
// `formats: ["iife"]` + `inlineDynamicImports: true` guarantees a single JS
// chunk (no code-splitting), matching the lutaml-xsd embedding pattern.
export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: { "@": resolve(root, "src") },
  },
  build: {
    target: "es2020",
    cssCodeSplit: false,
    minify: "terser",
    terserOptions: { compress: { drop_console: true } },
    // Library + iife format already emits a single self-executing chunk with no
    // code-splitting, so the bundle is one JS file the generator can inline.
    lib: {
      entry: resolve(root, "src/app.ts"),
      name: "RelatonIndex",
      fileName: () => "app.iife.js",
      formats: ["iife"],
    },
    rollupOptions: {
      output: {
        assetFileNames: "style.css",
      },
    },
  },
  define: {
    "process.env.NODE_ENV": JSON.stringify("production"),
  },
});
