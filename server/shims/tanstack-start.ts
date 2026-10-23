/**
 * Stand-in for the parts of `@tanstack/react-start` the server functions are written with, so the same files
 * run as a Supabase Edge Function without the web framework.
 *
 * - `createServerFn().middleware([…]).inputValidator(…).handler(…)` returns `({ data }) => result`, the
 *   shape `NATIVE_FNS` calls. Middleware runs first (sign-in check → 401 before a 400 for bad input), each
 *   `next({ context })` adding to the context the handler receives; then the input is validated.
 * - `createMiddleware().server(fn)` keeps `fn` for the above.
 * - `createIsomorphicFn().server(fn)` is `fn` (there is no browser side here); `createServerOnlyFn(fn)` is `fn`.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";

type Context = Record<string, unknown>;
/** What `requireSupabaseAuth` puts in the context (the only middleware the server functions use). */
type AuthContext = { supabase: SupabaseClient<Database>; userId: string; claims: Record<string, unknown> };
type Next = (opts?: { context?: Context }) => Promise<unknown>;
type MiddlewareServer = (opts: { next: Next; data: unknown; context: Context }) => Promise<unknown>;
export type Middleware = { __server: MiddlewareServer };

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Validator<T> = ((input: any) => T | Promise<T>) | { parse: (input: unknown) => T };

export function createMiddleware(_opts?: unknown) {
  return {
    server(fn: MiddlewareServer): Middleware {
      return { __server: fn };
    },
  };
}

type Builder<D> = {
  middleware(list: Middleware[]): Builder<D>;
  inputValidator<T>(v: Validator<T>): Builder<T>;
  handler<R>(
    fn: (opts: { data: D; context: AuthContext }) => R | Promise<R>,
  ): (opts?: { data?: unknown }) => Promise<Awaited<R>>;
};

export function createServerFn(_opts?: { method?: string }): Builder<undefined> {
  let middlewares: Middleware[] = [];
  let validate: ((input: unknown) => unknown) | null = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const builder: Builder<any> = {
    middleware(list) {
      middlewares = list;
      return builder;
    },
    inputValidator(v) {
      validate = typeof v === "function" ? v : (input) => v.parse(input);
      return builder;
    },
    handler(fn) {
      return async (opts = {}) => {
        let context: Context = {};
        const run = async (i: number): Promise<unknown> => {
          if (i < middlewares.length) {
            return middlewares[i].__server({
              data: opts.data,
              context,
              next: async (o) => {
                if (o?.context) context = { ...context, ...o.context };
                return run(i + 1);
              },
            });
          }
          const data = validate ? await validate(opts.data) : opts.data;
          return fn({ data, context: context as AuthContext });
        };
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return (await run(0)) as any;
      };
    },
  };
  return builder;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function createIsomorphicFn<F extends (...args: any[]) => any = (...args: any[]) => any>() {
  let server: F | null = null;
  const iso = ((...args: Parameters<F>) => {
    if (!server) throw new Error("createIsomorphicFn: no server implementation");
    return server(...args);
  }) as F & { server: (fn: F) => typeof iso; client: (fn: unknown) => typeof iso };
  iso.server = (fn: F) => {
    server = fn;
    return iso;
  };
  iso.client = () => iso;
  return iso;
}

export function createServerOnlyFn<F>(fn: F): F {
  return fn;
}
