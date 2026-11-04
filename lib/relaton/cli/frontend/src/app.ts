import { createApp, reactive } from "vue";
import App from "./App.vue";
import "./styles/index.css";
import { resolveIndex } from "./lib/hydrate";
import { createDetailLoader, loadSearchShards } from "./lib/shards";
import type { Hydration, IndexData } from "./lib/types";

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

// Off the critical path, but soon: the shell has nothing to show until the
// first shard lands, so this is only deferred past the initial paint. The
// `timeout` is not optional — without it an idle callback is not guaranteed to
// run at all, and a backgrounded or throttled tab would sit on an empty list
// forever, with every escape hatch (search, facets, a deep link) requiring the
// user to interact with a page showing nothing.
const IDLE_TIMEOUT_MS = 2000;

function whenIdle(cb: () => void): void {
  if (typeof window.requestIdleCallback === "function") {
    window.requestIdleCallback(() => cb(), { timeout: IDLE_TIMEOUT_MS });
  } else {
    window.setTimeout(cb, 0);
  }
}

function boot(): void {
  const el = document.getElementById(MOUNT_ID);
  if (!el) return;

  initTheme();

  const { data, shards } = resolveIndex(el);
  // `createApp(App, props)` props are static, so both of these have to be
  // reactive objects we mutate as shards arrive — reassigning a prop would not
  // reach the component.
  const state = reactive<IndexData>({ ...data });

  let started = false;
  function start(): void {
    if (started || shards.shards <= 0) return;
    started = true;
    loadSearchShards(shards, (docs) => {
      state.documents = docs;
    })
      .catch((err) => {
        // Individual shard failures are already handled inside the loader; this
        // only catches something unexpected, and must not surface as an
        // unhandled rejection.
        console.warn("relaton-index: shard load failed", err);
      })
      .finally(() => {
        hydration.loading = false;
      });
  }

  const hydration = reactive<Hydration>({
    loading: shards.shards > 0,
    total: shards.total,
    requestAll: start,
  });

  if (shards.shards > 0) whenIdle(start);

  createApp(App, {
    data: state,
    hydration,
    loadDetail: createDetailLoader(shards),
  }).mount(el);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot, { once: true });
} else {
  boot();
}
