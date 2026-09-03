# Deployment guide

How to stand this demo up in your own Snowflake account, end to end.

## Prerequisites

- A Snowflake account with `ACCOUNTADMIN` or equivalent (`CREATE DATABASE`, `CREATE AGENT`,
  `CREATE ROW ACCESS POLICY`, `CREATE STORAGE INTEGRATION` if you use the data engineering
  module's S3 path).
- Cortex Agents and Cortex Search enabled for your region (`CORTEX_ENABLED_CROSS_REGION` may
  need setting — check `SHOW PARAMETERS LIKE 'CORTEX%' IN ACCOUNT`).
- A default warehouse — everything here uses `COMPUTE_WH`; rename in the scripts if yours
  differs, or `ALTER WAREHOUSE COMPUTE_WH RENAME TO <yours>` first.
- Node.js 18+ and Python 3.11+ if you want to run the React app and the data engineering module.
- Snowflake CLI (`snow`) configured with a connection to your account.

## What this creates

Everything lands in a new `CUSTOM_DEMOS.DEEPKI` schema — nothing pre-existing in your account is
touched. Objects created:

- Tables, a semantic view, a Cortex Agent, and a Cortex Search service (`agent/`)
- Three roles and a row access policy proving multi-tenant isolation (`agent/05_row_access_policy.sql`)
- If you run the data engineering module: several `DE_`-prefixed tables, a Dynamic Table, a
  Snowpark stored procedure, three Tasks, and (if you do the S3 path) a storage integration and
  external stage

Estimated credit usage: low. The dataset is small (1,200 assets, ~40k fact rows), and the Tasks
in the data engineering module are suspended immediately after their one verification run — they
do not run on an ongoing schedule unless you resume them.

## Step 1 — Core demo

```bash
snow sql -c <your-connection> -f agent/01_create_tables.sql
snow sql -c <your-connection> -f agent/02_create_semantic_view.sql
snow sql -c <your-connection> -f agent/03_create_agent.sql
snow sql -c <your-connection> -f agent/05_row_access_policy.sql
```

Verify: `SHOW AGENTS IN SCHEMA CUSTOM_DEMOS.DEEPKI` should list `DEEPKI_PORTFOLIO_AGENT`.

## Step 2 — Data engineering module (optional)

```bash
snow sql -c <your-connection> -f data_engineering/01_ingest_semistructured_mongo.sql
```

For the real-S3 path (`02_ingest_parquet_s3.sql`), you need your own bucket and an IAM role.
This is a two-step handshake — do not skip the order:

1. Edit `data_engineering/02_ingest_parquet_s3.sql` and run only the `CREATE STORAGE INTEGRATION`
   and `DESCRIBE STORAGE INTEGRATION` statements first, with your own `<YOUR_AWS_ACCOUNT_ID>` in
   the role ARN placeholder (the role does not need to exist yet).
2. From the `DESCRIBE` output, note `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID`.
3. In AWS, create an IAM role trusting that IAM user with that external ID as a condition, and
   attach a policy granting `s3:GetObject`/`s3:ListBucket` scoped to your bucket/prefix only.
4. Generate and upload sample Parquet:
   ```bash
   python3 -m venv .venv && .venv/bin/pip install pandas pyarrow
   .venv/bin/python data_engineering/generate_and_upload_parquet.py \
       --bucket <your-bucket> --profile <your-aws-cli-profile>
   ```
5. Run the rest of `02_ingest_parquet_s3.sql` with your bucket/prefix substituted throughout.

Then the transformation and orchestration pieces:

```bash
snow sql -c <your-connection> -f data_engineering/03_transform_dynamic_tables.sql
.venv/bin/pip install snowflake-snowpark-python
.venv/bin/python data_engineering/04_transform_snowpark_procedure.py
snow sql -c <your-connection> -f data_engineering/05_orchestration_task_graph.sql
```

`04` and the task graph script connect using `~/.snowflake/connections.toml` by default — either
add a connection there matching the name used in the script, or edit the connection name at the
top of the file.

Verify: `SHOW DYNAMIC TABLES LIKE 'DE_%'` and `SHOW TASKS LIKE 'DE_%'` — all tasks should show
`state = suspended` once verification is done.

## Step 3 — React app

```bash
cd react-app
cp .env.example .env.local
```

Fill in `.env.local`:
- `SNOWFLAKE_ACCOUNT_URL` — your account's URL
- `SNOWFLAKE_PAT` — create one in Snowsight: your profile → Settings → Authentication →
  Programmatic access tokens. Scope it to a role with `USAGE` on the agent, the database/schema,
  and your warehouse.
- `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_SCHEMA` — `COMPUTE_WH`,
  `CUSTOM_DEMOS`, `DEEPKI` unless you renamed anything.

```bash
npm install
npm run dev
```

Open `http://localhost:3000`. Ask one of the three preset questions — expect a 30-90 second
response the first time while the warehouse resumes.

**Never commit `.env.local`** — it holds a live credential. It's already in `.gitignore`.

## Step 4 — Artefact and notebook

`DEMO_ARTIFACT.html` opens directly in any browser, no server required. `notebook/` is a
Snowflake Workspaces / Snowsight notebook — upload it and run all cells once before presenting;
the SQL and Snowpark cells were verified during the build, but re-running end to end after any
data changes is good practice.

## Cleanup / teardown

```sql
-- Core demo
DROP SCHEMA IF EXISTS CUSTOM_DEMOS.DEEPKI CASCADE;
DROP ROLE IF EXISTS DEEPKI_TENANT_RHENUS;
DROP ROLE IF EXISTS DEEPKI_TENANT_VANEAU;
DROP ROLE IF EXISTS DEEPKI_INTERNAL_ANALYST;

-- If you ran the data engineering module's S3 path
DROP STORAGE INTEGRATION IF EXISTS DE_S3_INTEGRATION;
```

In AWS, delete the IAM role you created and remove the uploaded Parquet objects from your bucket
if you no longer need them.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Agent call returns 401/403 | PAT expired or scoped to the wrong role — reissue |
| `agent:run` times out around 15 minutes | Normal API limit; the demo questions resolve well inside it (30-90s observed) |
| `STORAGE INTEGRATION` created but stage `LIST` shows nothing | IAM trust policy not yet propagated (wait ~10s) or wrong external ID/ARN copied |
| Task graph shows `FAILED` in `TASK_HISTORY` | Check `error_code`/`error_message` columns; most likely the Snowpark procedure wasn't deployed yet — run step 2's procedure script first |
| Semantic view or agent creation fails on synonyms | Synonyms must be globally unique across the whole semantic view — check for duplicates if you've edited it |
