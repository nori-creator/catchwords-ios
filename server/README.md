# server — the app's server functions (Supabase Edge Function `native-fn`)

Until 2026-10-20 the iOS app called the Lovable web app's server (`https://catchwords.lovable.app/api/native-fn`).
These are the same functions, moved here so the app no longer depends on Lovable:

- `src/` — the web app's server code (`src/lib`, `src/integrations/supabase`), copied from
  nori-creator/Lovable-catch-words-app at 761faf4 with only these changes:
  - the iOS check (`/api/native-fn`) also accepts the Edge Function's path (`/native-fn`)
  - tests that read the web app's screens (`src/components`, `src/hooks`, `src/routes`) were left out
- `shims/` — small stand-ins for the two TanStack Start modules the code imports (`createServerFn`, `getRequest`)
- `edge/native-fn.ts` — the Edge Function: `POST { fn, data }` with the user's Supabase token, same contract as before
- `build.mjs` — bundles everything into `supabase/functions/native-fn/bundle.js`

## Commands

```sh
npm ci
npm run typecheck   # TypeScript
npm test            # unit tests (vitest)
npm run build       # the bundle the deploy uploads
```

CI (`.github/workflows/server.yml`) runs all three on every change and deploys on `main`.

## Secrets (set on Supabase, never in this repository)

Supabase → Edge Functions → Secrets. The function finds the AI keys by these names:

| Name | What |
|---|---|
| `GEMINI_API_KEY` | Google AI Studio (Gemini) — the default AI |
| `ANTHROPIC_API_KEY` | Claude |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase itself.
