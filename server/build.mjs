/**
 * Bundles the server into one file for the Supabase Edge Function:
 *   server/edge/native-fn.ts → supabase/functions/native-fn/bundle.js
 *
 * Everything (our code and the npm packages) goes into the bundle, so the deploy does not depend on
 * fetching packages at deploy time. `node:` built-ins stay imports; the Edge runtime (Deno) provides them.
 * The two TanStack Start modules the web code imports are replaced by `shims/`.
 */
import { builtinModules } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as esbuild from "esbuild";

/** Packages that `require("fs")` etc. get the `node:` module Deno provides. */
const nodeBuiltins = {
  name: "node-builtins",
  setup(build) {
    const names = new Set(builtinModules.filter((m) => !m.startsWith("_")));
    build.onResolve({ filter: /^[a-z_/]+$/ }, (args) =>
      names.has(args.path) ? { path: `node:${args.path}`, external: true } : undefined,
    );
  },
};

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, "../supabase/functions/native-fn/bundle.js");

const result = await esbuild.build({
  entryPoints: [path.join(here, "edge/native-fn.ts")],
  outfile: out,
  bundle: true,
  format: "esm",
  platform: "neutral",
  target: "es2022",
  mainFields: ["module", "main"],
  conditions: ["deno", "worker", "import", "default"],
  external: ["node:*"],
  plugins: [nodeBuiltins],
  alias: {
    "@tanstack/react-start/server": path.join(here, "shims/tanstack-start-server.ts"),
    "@tanstack/react-start": path.join(here, "shims/tanstack-start.ts"),
    "@": path.join(here, "src"),
  },
  define: { "process.env.NODE_ENV": '"production"' },
  // The server code reads `process.env.*` the Node way, and a few CommonJS packages call `require`;
  // Deno provides both through `node:` modules.
  banner: {
    js: [
      'import __process from "node:process";',
      'import { createRequire as __createRequire } from "node:module";',
      "globalThis.process ??= __process;",
      "const require = __createRequire(import.meta.url);",
    ].join("\n"),
  },
  legalComments: "none",
  // Supabase refuses a function over 5 MB (the unminified bundle was 5.17 MB). Minified, with names kept so
  // error messages and stack traces still say which function failed.
  minify: true,
  keepNames: true,
  metafile: true,
  logLevel: "warning",
});

const bytes = Object.values(result.metafile.outputs).reduce((sum, o) => sum + o.bytes, 0);
console.log(`native-fn bundle: ${(bytes / 1e6).toFixed(2)} MB → ${path.relative(process.cwd(), out)}`);
// Leave room under Supabase's 5 MB deploy limit (index.ts is uploaded beside it).
if (bytes > 4.5e6) {
  console.error("native-fn bundle is over 4.5 MB; Supabase refuses a function over 5 MB.");
  process.exit(1);
}
