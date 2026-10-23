/**
 * Stand-in for `@tanstack/react-start/server` (the web app ran these functions inside TanStack Start).
 *
 * Only `getRequest` is used by the server code: the signed-in caller's `Authorization` header, the
 * `AI-Consent-Version` header and `waitUntil` for work that continues after the answer. The Edge Function
 * entry (`edge/native-fn.ts`) runs every call inside `runWithRequest`, so each call sees its own request.
 */
import { AsyncLocalStorage } from "node:async_hooks";

const store = new AsyncLocalStorage<Request>();

export function runWithRequest<T>(request: Request, fn: () => Promise<T>): Promise<T> {
  return store.run(request, fn);
}

/**
 * The request being answered. Typed as always present like TanStack's; outside a request (tests, work after
 * the answer) it is undefined, which the callers already guard with `?.` or try/catch.
 */
export function getRequest(): Request {
  return store.getStore() as Request;
}
