-- =====================================================================
-- Data engineering demo — Mongo-style semi-structured ingestion
--
-- Deepki's real primary database is MongoDB. Romain named the NoSQL-to-
-- structured transition as the biggest architectural difficulty, and it
-- is the first thing this module addresses.
--
-- In production this table is what OpenFlow (NiFi-based, JDBC/ODBC to
-- MongoDB) would land: raw documents, one row per document, untouched.
-- OpenFlow itself isn't deployed here — a live NiFi flow against a real
-- Mongo cluster isn't something a repo can reproduce — but the shape of
-- what it delivers, and what happens to it next, is real and runnable.
--
-- All objects here are prefixed DE_ and live alongside the existing
-- agent/semantic-view objects in CUSTOM_DEMOS.DEEPKI without touching them.
-- =====================================================================

USE SCHEMA CUSTOM_DEMOS.DEEPKI;

-- ---------------------------------------------------------------------
-- Landing table: one row per Mongo document, exactly as delivered.
-- No schema imposed at load time, which is the point of landing VARIANT
-- first — the structure decision happens downstream, not at ingest.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DE_RAW_MONGO_ASSET_DOCUMENTS (
    document_id   VARCHAR(30)   PRIMARY KEY,
    landed_at     TIMESTAMP_TZ  DEFAULT CURRENT_TIMESTAMP(),
    source_system VARCHAR(40)   DEFAULT 'mongo_assets_collection',
    payload       VARIANT       NOT NULL
)
COMMENT = 'Raw Mongo-shaped documents, one row per document. Stands in for what OpenFlow (NiFi, JDBC/ODBC) would land from the real MongoDB cluster.';

-- 40 documents, nested the way a real Mongo export reads: location and
-- metering as sub-objects, retrofit history as an array. Deliberately a
-- different shape from RAW_ASSET_REGISTER (which models the CSV/Parquet
-- feed) — Deepki's real environment has both shapes at once.
INSERT INTO DE_RAW_MONGO_ASSET_DOCUMENTS (document_id, payload)
SELECT
    '_id_' || LPAD(n::VARCHAR, 5, '0'),
    PARSE_JSON(
        '{'
        || '"_id": "' || LPAD(n::VARCHAR, 5, '0') || '",'
        || '"client_ref": "' || client_id || '",'
        || '"asset_name": "' || asset_name || '",'
        || '"location": {"country": "' || country || '", "city": "' || city || '"},'
        || '"sector": "' || sector || '",'
        || '"floor_area": {"value": ' || floor_area || ', "unit": "sqm"},'
        || '"metering": {"heating_system": "' || heating || '", "epc_rating": "' || epc || '"},'
        || '"retrofit_history": [' || retrofit_history || '],'
        || '"last_synced": "2026-06-30T00:00:00Z"'
        || '}'
    )
FROM (
    SELECT
        SEQ4() + 1 AS n,
        CASE MOD(SEQ4(), 5)
            WHEN 0 THEN 'CL001' WHEN 1 THEN 'CL002' WHEN 2 THEN 'CL003'
            WHEN 3 THEN 'CL004' ELSE 'CL006'
        END AS client_id,
        'Mongo-sourced site ' || (SEQ4() + 1)::VARCHAR AS asset_name,
        CASE MOD(SEQ4(), 4)
            WHEN 0 THEN 'France' WHEN 1 THEN 'Germany'
            WHEN 2 THEN 'Spain' ELSE 'Italy'
        END AS country,
        CASE MOD(SEQ4(), 4)
            WHEN 0 THEN 'Lyon' WHEN 1 THEN 'Munich'
            WHEN 2 THEN 'Valencia' ELSE 'Turin'
        END AS city,
        CASE MOD(SEQ4(), 3)
            WHEN 0 THEN 'Office' WHEN 1 THEN 'Retail' ELSE 'Logistics'
        END AS sector,
        3200 + MOD(SEQ4() * 137, 9800) AS floor_area,
        CASE MOD(SEQ4(), 4)
            WHEN 0 THEN 'Gas boiler' WHEN 1 THEN 'Heat pump'
            WHEN 2 THEN 'District heating' ELSE 'Electric resistance'
        END AS heating,
        CASE MOD(SEQ4(), 7)
            WHEN 0 THEN 'A' WHEN 1 THEN 'B' WHEN 2 THEN 'C' WHEN 3 THEN 'D'
            WHEN 4 THEN 'E' WHEN 5 THEN 'F' ELSE 'G'
        END AS epc,
        -- Retrofit history: 0-2 entries, an array of sub-objects, the
        -- kind of nesting that makes flattening non-trivial at scale.
        CASE MOD(SEQ4(), 3)
            WHEN 0 THEN ''
            WHEN 1 THEN '{"year": 2024, "action": "LED relighting"}'
            ELSE '{"year": 2023, "action": "BMS optimisation"}, {"year": 2025, "action": "Roof insulation"}'
        END AS retrofit_history
    FROM TABLE(GENERATOR(ROWCOUNT => 40))
);

-- ---------------------------------------------------------------------
-- Flattened view: the semi-structured-to-structured step.
--
-- This is the exact transition Romain called the hardest part of moving
-- off Mongo. It is a view, not a table, so it costs nothing to keep in
-- sync as new documents land — the flattening logic lives in one place
-- and every consumer downstream (the Dynamic Table in 03, a BI tool,
-- another agent) reads the same definition.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW DE_STG_ASSET_FROM_MONGO AS
SELECT
    m.document_id,
    m.payload:client_ref::VARCHAR                    AS client_id,
    m.payload:asset_name::VARCHAR                     AS asset_name,
    m.payload:location:country::VARCHAR               AS asset_country,
    m.payload:location:city::VARCHAR                  AS asset_city,
    m.payload:sector::VARCHAR                         AS asset_sector,
    m.payload:floor_area:value::NUMBER(12,2)          AS floor_area_m2,
    m.payload:metering:heating_system::VARCHAR        AS heating_system,
    m.payload:metering:epc_rating::VARCHAR             AS epc_rating,
    ARRAY_SIZE(m.payload:retrofit_history)             AS retrofit_count,
    m.payload:retrofit_history                         AS retrofit_history_raw,
    m.payload:last_synced::TIMESTAMP_TZ                AS mongo_last_synced,
    m.landed_at
FROM DE_RAW_MONGO_ASSET_DOCUMENTS m;

-- Smoke test: confirm the flatten works and nothing is silently NULL.
SELECT COUNT(*) AS documents,
       COUNT(client_id) AS with_client_id,
       COUNT(floor_area_m2) AS with_floor_area,
       SUM(retrofit_count) AS total_retrofit_entries
FROM DE_STG_ASSET_FROM_MONGO;
