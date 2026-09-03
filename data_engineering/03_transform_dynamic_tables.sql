-- =====================================================================
-- Data engineering demo — Dynamic Tables for transformation
--
-- The transcript names this explicitly: "Stream et Tâche et Dynamic
-- Table, c'est de la transformation en SQL." A Dynamic Table replaces the
-- manual CREATE-TABLE-AS-SELECT-and-rerun-it-yourself pattern used
-- elsewhere in this repo: define the query once, set a target lag, and
-- Snowflake keeps it current — incrementally where it can, without a
-- Stream or a Task written by hand to drive it.
--
-- This one deliberately reads from BOTH ingestion paths built in 01 and
-- 02 — the Mongo-shaped documents and the S3 Parquet load — because that
-- is the real shape of Deepki's problem: two sources describing
-- overlapping parts of one portfolio, and one governed place where they
-- get reconciled into a single row grain.
-- =====================================================================

USE SCHEMA CUSTOM_DEMOS.DEEPKI;

CREATE OR REPLACE DYNAMIC TABLE DE_DT_ASSET_HARMONISED
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
  COMMENT = 'Harmonised asset view auto-refreshed from two source systems (Mongo-shaped documents, S3 Parquet). No Stream or Task was written by hand for this — the Dynamic Table schedules its own incremental refresh.'
AS
SELECT
    document_id                       AS source_ref,
    'mongo'                            AS source_system,
    client_id,
    asset_name,
    asset_country,
    asset_city,
    asset_sector,
    floor_area_m2,
    heating_system,
    epc_rating
FROM DE_STG_ASSET_FROM_MONGO

UNION ALL

SELECT
    asset_ref,
    'parquet_s3',
    client_ref,
    NULL,
    country,
    city,
    sector,
    floor_area_sqm,
    heating_system,
    epc_rating
FROM DE_RAW_ASSET_PARQUET;

-- Dynamic Tables refresh on schedule; force one now rather than waiting
-- on TARGET_LAG for the demo.
ALTER DYNAMIC TABLE DE_DT_ASSET_HARMONISED REFRESH;

-- Confirm the two sources both landed and the row count matches what
-- 01 and 02 loaded independently (40 Mongo documents + 60 Parquet rows).
SELECT source_system, COUNT(*) AS assets, COUNT(DISTINCT client_id) AS clients
FROM DE_DT_ASSET_HARMONISED
GROUP BY source_system
ORDER BY source_system;

-- Cross-check against the client dimension the rest of the demo already
-- uses: every client_id referenced by either source must resolve to a
-- real Deepki client, which is the same equivalence-check discipline
-- used in the build notebook.
SELECT dt.client_id, dt.source_system, c.client_name
FROM DE_DT_ASSET_HARMONISED dt
LEFT JOIN DIM_CLIENT c ON c.client_id = dt.client_id
WHERE c.client_id IS NULL;
-- Expected: zero rows. Every client_id in either source is a real client.

SHOW DYNAMIC TABLES LIKE 'DE_DT_ASSET_HARMONISED';
