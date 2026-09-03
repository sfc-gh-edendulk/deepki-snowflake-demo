# Deepki Portfolio Copilot

A Next.js panel that talks to a Snowflake Cortex Agent over the REST API. It plays the
part of a copilot embedded in Deepki's own real-estate ESG product, used by an energy
manager who wants to know which buildings are off their CRREM decarbonisation pathway
and what to do about it.

Two data paths, deliberately different:

| Surface | Path | Why |
|---|---|---|
| KPI strip | `GET /api/portfolio` → `querySnowflake` on `ASSET_YEAR_PERFORMANCE` | Four headline numbers, needed instantly |
| Copilot chat | `POST /api/agent` → `DEEPKI_PORTFOLIO_AGENT:run` | The agent plans, writes SQL, and explains — 30-90 seconds per answer |

The chat panel shows which tools the agent chose for each answer. That is the point of
the demo: the agent is not running a canned query, it is deciding how to answer.

## Snowflake objects

Everything lives in `CUSTOM_DEMOS.DEEPKI`:

- `DEEPKI_PORTFOLIO_AGENT` — the Cortex Agent
- `ASSET_YEAR_PERFORMANCE` — per-asset, per-year energy, CO2e and CRREM pathway gap
- `CLIENT_YEAR_EXPOSURE` — per-client stranded area and subscription exposure
- `DIM_CLIENT`, `DIM_ASSET` — client and building attributes

## Prerequisites

1. The `CUSTOM_DEMOS.DEEPKI` schema built and populated.
2. `DEEPKI_PORTFOLIO_AGENT` created and working.
3. A programmatic access token (PAT) for the agent REST API — see below.

## Creating the PAT

The agent REST endpoint authenticates with a programmatic access token, not a password.
In Snowsight: **Profile → Settings → Authentication → Programmatic access tokens → Generate
new token**. Scope it to the role that can use the agent (`ACCOUNTADMIN` in this demo) and
copy the value immediately — it is shown once.

Equivalent SQL:

```sql
ALTER USER AI_USER ADD PROGRAMMATIC ACCESS TOKEN deepki_copilot
  ROLE_RESTRICTION = 'ACCOUNTADMIN'
  DAYS_TO_EXPIRY = 30;
```

The user must also have a network policy attached, or Snowflake refuses to mint the token.

## Local development

```bash
cp .env.example .env.local   # then fill in SNOWFLAKE_PASSWORD and SNOWFLAKE_PAT
npm install
npm run dev
```

Open http://localhost:3000.

`.env.local` holds live credentials and must never be committed. `SNOWFLAKE_PAT` is read
server-side only, in `app/api/agent/route.ts`; the browser never sees it.

The KPI strip uses the SDK (password auth, or your `~/.snowflake/config.toml` default
connection if `SNOWFLAKE_USER`/`SNOWFLAKE_PASSWORD` are unset). The agent route always
needs the PAT.

## Checks

```bash
npx tsc --noEmit
npm run build
```

Note that `next.config.mjs` sets `typescript.ignoreBuildErrors: true`, so `npm run build`
alone will not catch type errors. Run `tsc --noEmit` too.

## Known limits

- **Non-streaming only.** The agent is called with `stream: false`, so the answer appears
  all at once after 30-90 seconds. The panel counts elapsed seconds rather than pretending
  to stream.
- **Charts are not drawn.** When the agent returns a Vega-Lite spec, the panel renders the
  accompanying result table and notes that a spec was returned. Drawing an approximation
  the agent did not specify would misrepresent its output; adding a Vega runtime is the
  real fix.
- **No SPCS deployment is configured.** `app.yml` and `next.config.mjs` are inherited from
  the template and are deployment-ready in shape, but nothing here has been deployed and
  the PAT is not wired up as a Snowflake secret. This runs locally.
