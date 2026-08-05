// Dev-only entry: inject a sample dataset onto window, then boot the app.
// Excluded from the production library build (which uses src/app.ts).
import sample from "./sample-data.json";
import type { IndexData } from "../lib/types";

window.RELATON_INDEX_DATA = sample as IndexData;

import("../app");
