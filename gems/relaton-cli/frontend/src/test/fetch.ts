import { vi } from "vitest";

// Minimal fetch stub for the shard loaders. Routes are keyed by the file name
// (the last path segment), which is how the loaders address shards.
//
// A route value may be:
//   * a value          — served as JSON with status 200
//   * a number         — served as that HTTP status with no body (for 404 tests)
//   * a Promise        — resolved when it resolves (for out-of-order tests)
//   * a function       — called per request, returning any of the above
// An unrouted path 404s, so a test only declares the shards it cares about.

export type Route = unknown | Promise<unknown> | (() => unknown);

export interface FetchStub {
  /** Paths requested, in call order. */
  calls: string[];
  restore: () => void;
}

function respond(body: unknown): Response {
  if (typeof body === "number") {
    return new Response(null, { status: body });
  }
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

export function stubFetch(routes: Record<string, Route>): FetchStub {
  const calls: string[] = [];

  const impl = async (input: RequestInfo | URL): Promise<Response> => {
    const url =
      typeof input === "string" ? input : String((input as Request).url ?? input);
    calls.push(url);

    const name = url.split("/").pop() ?? "";
    if (!(name in routes)) return new Response(null, { status: 404 });

    let value = routes[name];
    if (typeof value === "function") value = (value as () => unknown)();
    return respond(await value);
  };

  vi.stubGlobal("fetch", vi.fn(impl));
  return { calls, restore: () => vi.unstubAllGlobals() };
}

/** A promise plus the handle to settle it, for controlling resolution order. */
export function deferred<T>(): { promise: Promise<T>; resolve: (v: T) => void } {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}
