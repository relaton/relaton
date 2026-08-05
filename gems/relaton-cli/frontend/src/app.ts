import { createApp } from "vue";
import App from "./App.vue";
import "./styles/index.css";
import { resolveIndexData } from "./lib/hydrate";
import type { IndexData } from "./lib/types";

const MOUNT_ID = "relaton-index-app";

// Restore the persisted theme (or fall back to the OS preference) before the
// app paints, so there's no light→dark flash.
function initTheme(): void {
  try {
    const stored = localStorage.getItem("relaton-index-theme");
    const dark =
      stored === "dark" ||
      (stored === null &&
        window.matchMedia?.("(prefers-color-scheme: dark)").matches);
    document.documentElement.classList.toggle("dark", !!dark);
  } catch {
    /* localStorage/matchMedia may be unavailable; ignore. */
  }
}

function boot(): void {
  const el = document.getElementById(MOUNT_ID);
  if (!el) return;

  initTheme();

  resolveIndexData(el).then((data: IndexData) => {
    // Remove the crawler-only DOM so Vue owns the subtree cleanly.
    el.querySelector(".documents")?.remove();
    createApp(App, { data }).mount(el);
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot, { once: true });
} else {
  boot();
}
