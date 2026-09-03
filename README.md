# Deepki — Snowflake Cortex Agent Demo

A customer-specific demo built for the Deepki technical deep dive (3 September 2026).

Deepki is a French ESG data intelligence platform for real estate: 600+ clients, ~$4T of
assets monitored, hundreds of thousands of buildings across 41 countries. They ingest utility
bills and smart-meter data, benchmark portfolios, and publish the Deepki Index.

## What this demo argues

Deepki named their own problems in the 7 July discovery call. Each asset here answers one of
them rather than touring Snowflake features.

| What Deepki said | What this demo shows |
|---|---|
| Users have no autonomy — everything goes through the R&D team | An agent answering an energy manager's question with no data scientist in the loop |
| A recently acquired company gives its energy managers autonomy through a lakehouse | The same autonomy, embedded in a Deepki-branded product surface |
| "We are sitting on a mountain of gold data we barely exploit" | A question that spans four source systems and cannot be answered from any one of them |
| Churn happens because energy managers lack tooling | The headline metric is subscription revenue at risk |
| Client isolation, and scope isolation within a client, is non-negotiable (ISO, SOC) | A row access policy: same agent, same question, tenant-scoped answers |
| The data model must flex per client — offices want kWh/m², nursing homes want per-occupied-room | Two intensity metrics in one semantic view; the agent picks by sector |
| No semantic layer today | The semantic view is the centrepiece, not an implementation detail |
| Meter data is noisy and sparse | An explicit data-quality flag in the silver layer, not hidden |

## The three-act arc

- **WHAT** — Across the portfolios we monitor, how much floor area is already off its CRREM
  decarbonisation pathway, and how much annual subscription revenue sits with the most
  exposed clients?
- **WHY** — Which client drives the largest share of that stranded floor area, and what is the
  pattern by sector, country and heating system?
- **HOW + ACTION** — What retrofit actions do you recommend for that client's worst assets,
  and what is the payback? Then draft the email to their named energy manager.

The WHAT question crosses four domains on purpose: consumption lives in metering systems,
floor area and sector live in the client's asset management system, the pathway threshold is
external regulatory data, and subscription value lives in Deepki's own commercial system.

## Layout

```
agent/
  01_create_tables.sql        raw + harmonised tables, synthetic data
  02_create_semantic_view.sql sector-aware semantic view
  03_create_agent.sql         Cortex Agent (analyst + search tools)
  04_example_questions.md     the three arc questions, tested
  05_row_access_policy.sql    multi-tenant isolation proof
data_engineering/             ingestion, transformation and orchestration — see its own README
react-app/                    Next.js app calling the agent:run REST API
notebook/                     raw-to-governed build notebook, SQL and Snowpark side by side
DEMO_ARTIFACT.html            self-contained visual answering the WHAT question
```

## Data engineering

`data_engineering/` is a separate module answering the ingestion, transformation and
orchestration questions raised in the technical dive: a Mongo-shaped semi-structured ingestion
path, a real S3-to-Snowflake Parquet path (native and external table), a Dynamic Table, a pure
Python Snowpark stored procedure, and a Task Graph. See `data_engineering/README.md` for the
detail — including exactly which parts were verified live and which are intentionally left for
the workshop (dbt Core, a full Iceberg catalog table).

## Deploying into your own account

This was built and verified against a Snowflake trial-style account in AWS eu-central-1
(Frankfurt), the same region recommended for EU data residency. It is written to be portable to
any Snowflake account — see `DEPLOYMENT.md` for step-by-step setup, prerequisites, and estimated
credit usage.

## Running it

```bash
# 1. Data, semantic view, agent (replace <your-connection> with your own)
snow sql -c <your-connection> -f agent/01_create_tables.sql
snow sql -c <your-connection> -f agent/02_create_semantic_view.sql
snow sql -c <your-connection> -f agent/03_create_agent.sql
snow sql -c <your-connection> -f agent/05_row_access_policy.sql

# 2. Data engineering module (optional, see data_engineering/README.md)
snow sql -c <your-connection> -f data_engineering/01_ingest_semistructured_mongo.sql
snow sql -c <your-connection> -f data_engineering/03_transform_dynamic_tables.sql
.venv/bin/python data_engineering/04_transform_snowpark_procedure.py
snow sql -c <your-connection> -f data_engineering/05_orchestration_task_graph.sql

# 3. React app (localhost)
cd react-app && cp .env.example .env.local   # then add a PAT — see DEPLOYMENT.md
npm install && npm run dev

# 4. Artefact
open DEMO_ARTIFACT.html
```

Full details, including the S3/IAM setup for the data engineering module and the exact PAT
creation steps, are in `DEPLOYMENT.md`.

The React app runs on localhost by default. No Snowflake App Runtime deployment is included —
that is a separate step covered in `DEPLOYMENT.md` if you want a hosted URL rather than a local
dev server.
