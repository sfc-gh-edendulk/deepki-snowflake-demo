-- =====================================================================
-- Data engineering demo — Parquet from a real S3 bucket
--
-- Deepki already has some data in Parquet on S3. Jean-Philippe asked
-- specifically whether Snowflake can connect to an existing bucket rather
-- than requiring a Snowflake-owned one. This script is the real answer,
-- run against a real bucket, not a simulation.
--
-- IMPORTANT — before running this against your own account:
-- The <YOUR_...> placeholders below stand in for a real AWS account ID and a
-- real S3 bucket in a Snowflake build environment where this was verified
-- end to end (IAM role, trust handshake, native and external tables both
-- agreeing on row count and totals). Replace every placeholder with your
-- own account ID and bucket/prefix before running this. See DEPLOYMENT.md.
--
-- The two-step handshake below is not optional boilerplate — Snowflake's
-- IAM user ARN and external ID for STORAGE_AWS_ROLE_ARN only exist after
-- the integration is created, so the AWS-side trust policy is created
-- second, using values read back from Snowflake. Order matters:
--   1. CREATE STORAGE INTEGRATION (with a role ARN that need not exist yet)
--   2. DESCRIBE STORAGE INTEGRATION -> read STORAGE_AWS_IAM_USER_ARN,
--      STORAGE_AWS_EXTERNAL_ID
--   3. In AWS: create the IAM role, trust policy referencing those two
--      values, attach an S3 read policy scoped to the exact prefix
--   4. CREATE STAGE, referencing the integration
-- =====================================================================

USE SCHEMA CUSTOM_DEMOS.DEEPKI;

CREATE OR REPLACE STORAGE INTEGRATION DE_S3_INTEGRATION
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/deepki-demo-snowflake-de-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://<YOUR_S3_BUCKET>/<YOUR_PREFIX>/')
  COMMENT = 'Scoped to one prefix, not the whole bucket — the principle of least privilege applies to storage integrations the same as to roles.';

-- Run this, then go create/update the AWS IAM role using the two values
-- it prints (STORAGE_AWS_IAM_USER_ARN, STORAGE_AWS_EXTERNAL_ID) before
-- continuing. See the AWS role and policy templates in this file's
-- companion, `02b_aws_iam_role_template.md`.
DESCRIBE STORAGE INTEGRATION DE_S3_INTEGRATION;

CREATE OR REPLACE STAGE DE_STAGE_ASSET_PARQUET
  URL = 's3://<YOUR_S3_BUCKET>/<YOUR_PREFIX>/'
  STORAGE_INTEGRATION = DE_S3_INTEGRATION
  FILE_FORMAT = (TYPE = PARQUET)
  COMMENT = 'External stage over the client-owned S3 prefix. Snowflake never copies or owns this data at rest here.';

-- Confirms the trust handshake worked: Snowflake can see the objects in
-- a bucket it does not own, through a role it was never given static
-- credentials for.
LIST @DE_STAGE_ASSET_PARQUET;

-- ---------------------------------------------------------------------
-- Path A: native table via COPY INTO. Elizabeth's "ingest into managed
-- Snowflake tables" option — full micro-partitioning and pruning, data
-- physically lands in Snowflake.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DE_RAW_ASSET_PARQUET (
    asset_ref         VARCHAR(20),
    client_ref        VARCHAR(10),
    country           VARCHAR(40),
    city              VARCHAR(60),
    sector            VARCHAR(40),
    floor_area_sqm    NUMBER(12,2),
    heating_system    VARCHAR(40),
    epc_rating        VARCHAR(4),
    build_year        NUMBER(4,0),
    source_file_batch VARCHAR(20),
    ingested_at       TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Loaded via COPY INTO from the external stage. Physically resident in Snowflake, fully micro-partitioned.';

COPY INTO DE_RAW_ASSET_PARQUET
    (asset_ref, client_ref, country, city, sector, floor_area_sqm,
     heating_system, epc_rating, build_year, source_file_batch)
FROM (
    SELECT
        $1:asset_ref::VARCHAR,        $1:client_ref::VARCHAR,
        $1:country::VARCHAR,          $1:city::VARCHAR,
        $1:sector::VARCHAR,           $1:floor_area_sqm::NUMBER(12,2),
        $1:heating_system::VARCHAR,   $1:epc_rating::VARCHAR,
        $1:build_year::NUMBER(4,0),   $1:source_file_batch::VARCHAR
    FROM @DE_STAGE_ASSET_PARQUET
)
FILE_FORMAT = (TYPE = PARQUET);

-- ---------------------------------------------------------------------
-- Path B: external table. Elizabeth's "connect the bucket, see it as
-- metadata" option — no COPY, no physical residency, queries reach out
-- to S3 through the stage every time. Cheaper to keep in sync (nothing
-- to refresh unless the file list changes), slower per query.
-- ---------------------------------------------------------------------
CREATE OR REPLACE EXTERNAL TABLE DE_EXT_ASSET_PARQUET (
    asset_ref      VARCHAR AS (value:asset_ref::VARCHAR),
    client_ref     VARCHAR AS (value:client_ref::VARCHAR),
    floor_area_sqm NUMBER(12,2) AS (value:floor_area_sqm::NUMBER(12,2)),
    sector         VARCHAR AS (value:sector::VARCHAR)
)
LOCATION = @DE_STAGE_ASSET_PARQUET
FILE_FORMAT = (TYPE = PARQUET)
COMMENT = 'Query-in-place over the same S3 prefix. No COPY step, no physical copy in Snowflake.';

-- Both paths should agree on row count and on a couple of real values.
SELECT 'native (COPY INTO)' AS path, COUNT(*) AS row_count, SUM(floor_area_sqm) AS total_m2
FROM DE_RAW_ASSET_PARQUET
UNION ALL
SELECT 'external (query in place)', COUNT(*), SUM(floor_area_sqm)
FROM DE_EXT_ASSET_PARQUET;

-- ---------------------------------------------------------------------
-- Iceberg: cut from this build, on purpose.
--
-- Elizabeth recommended Iceberg for bronze/silver and native tables for
-- gold. A working Iceberg table over an existing bucket needs an EXTERNAL
-- VOLUME, which is a second IAM role and trust handshake identical in
-- shape to the one above, plus Iceberg table metadata that a plain
-- Parquet file does not carry on its own. Rather than half-build that and
-- call it verified, this module stops at native + external tables, both
-- genuinely running against the real bucket above. The Iceberg path is
-- the same mechanism, one more IAM role away — worth doing live in the
-- workshop rather than in this repo.
-- ---------------------------------------------------------------------
