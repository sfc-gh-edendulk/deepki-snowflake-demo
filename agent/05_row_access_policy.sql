-- =====================================================================
-- Deepki demo — multi-tenant isolation
--
-- Jean-Philippe raised this twice on the 7 July call, in stronger terms
-- than anything else: isolation between clients, and isolation of scopes
-- within a client, is what they have to guarantee to hold their ISO
-- certification and their SOC report. His words were that without it
-- "on se trouve tout nu".
--
-- The proof to show is not a slide. It is the same agent, asked the same
-- question, returning a scoped answer depending on who is asking.
--
-- Important behaviour to know before demoing: Cortex Agents resolve
-- permissions from the querying user's DEFAULT role, not the role active
-- in the session. So a tenant-scoped agent call needs a user whose
-- default role is the tenant role, and that user also needs a default
-- warehouse. Switching role mid-session is enough to prove the policy on
-- plain SQL, but not to prove it through the agent.
-- =====================================================================

USE SCHEMA CUSTOM_DEMOS.DEEPKI;

-- ---------------------------------------------------------------------
-- Role to client mapping. In production this would be driven by the
-- identity provider rather than a table, but the mechanism is the same.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE TENANT_ROLE_MAP (
    role_name  VARCHAR(60) NOT NULL,
    client_id  VARCHAR(10) NOT NULL,
    scope_note VARCHAR(200),
    PRIMARY KEY (role_name, client_id)
)
COMMENT = 'Maps a Snowflake role to the client whose data it may see.';

INSERT INTO TENANT_ROLE_MAP VALUES
    ('DEEPKI_TENANT_RHENUS', 'CL002', 'Rhenus Immobilien GmbH energy managers. German care and office portfolio.'),
    ('DEEPKI_TENANT_VANEAU', 'CL001', 'Vaneau Asset Management energy managers. French portfolio.');

-- ---------------------------------------------------------------------
-- Roles. DEEPKI_INTERNAL_ANALYST stands in for Deepki's own staff, who
-- legitimately see the whole book.
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS DEEPKI_TENANT_RHENUS;
CREATE ROLE IF NOT EXISTS DEEPKI_TENANT_VANEAU;
CREATE ROLE IF NOT EXISTS DEEPKI_INTERNAL_ANALYST;

GRANT USAGE ON DATABASE CUSTOM_DEMOS TO ROLE DEEPKI_TENANT_RHENUS;
GRANT USAGE ON DATABASE CUSTOM_DEMOS TO ROLE DEEPKI_TENANT_VANEAU;
GRANT USAGE ON DATABASE CUSTOM_DEMOS TO ROLE DEEPKI_INTERNAL_ANALYST;
GRANT USAGE ON SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_TENANT_RHENUS;
GRANT USAGE ON SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_TENANT_VANEAU;
GRANT USAGE ON SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_INTERNAL_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_TENANT_RHENUS;
GRANT SELECT ON ALL TABLES IN SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_TENANT_VANEAU;
GRANT SELECT ON ALL TABLES IN SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_INTERNAL_ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_TENANT_RHENUS;
GRANT SELECT ON ALL VIEWS IN SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_TENANT_VANEAU;
GRANT SELECT ON ALL VIEWS IN SCHEMA CUSTOM_DEMOS.DEEPKI TO ROLE DEEPKI_INTERNAL_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DEEPKI_TENANT_RHENUS;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DEEPKI_TENANT_VANEAU;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DEEPKI_INTERNAL_ANALYST;

-- Semantic view and agent access, so a tenant role can use the copilot.
GRANT SELECT ON SEMANTIC VIEW CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_SV TO ROLE DEEPKI_TENANT_RHENUS;
GRANT SELECT ON SEMANTIC VIEW CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_SV TO ROLE DEEPKI_TENANT_VANEAU;
GRANT SELECT ON SEMANTIC VIEW CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_SV TO ROLE DEEPKI_INTERNAL_ANALYST;
GRANT USAGE ON AGENT CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_AGENT TO ROLE DEEPKI_TENANT_RHENUS;
GRANT USAGE ON AGENT CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_AGENT TO ROLE DEEPKI_TENANT_VANEAU;
GRANT USAGE ON AGENT CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_AGENT TO ROLE DEEPKI_INTERNAL_ANALYST;
GRANT USAGE ON CORTEX SEARCH SERVICE CUSTOM_DEMOS.DEEPKI.DEEPKI_ESG_KNOWLEDGE_SEARCH TO ROLE DEEPKI_TENANT_RHENUS;
GRANT USAGE ON CORTEX SEARCH SERVICE CUSTOM_DEMOS.DEEPKI.DEEPKI_ESG_KNOWLEDGE_SEARCH TO ROLE DEEPKI_TENANT_VANEAU;
GRANT USAGE ON CORTEX SEARCH SERVICE CUSTOM_DEMOS.DEEPKI.DEEPKI_ESG_KNOWLEDGE_SEARCH TO ROLE DEEPKI_INTERNAL_ANALYST;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE DEEPKI_TENANT_RHENUS;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE DEEPKI_TENANT_VANEAU;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE DEEPKI_INTERNAL_ANALYST;

-- ---------------------------------------------------------------------
-- One policy, applied to every table carrying a client_id.
--
-- Deepki's own staff and the deploying role see everything; a tenant role
-- sees only the client it is mapped to; anything else sees nothing. The
-- default is deny, which is the only safe default for a multi-tenant
-- platform.
-- ---------------------------------------------------------------------
-- Detach first so this script can be re-run. DROP ALL ROW ACCESS POLICIES
-- is tolerant of there being none, unlike dropping a named policy.
ALTER TABLE DIM_ASSET            DROP ALL ROW ACCESS POLICIES;
ALTER TABLE DIM_CLIENT           DROP ALL ROW ACCESS POLICIES;
ALTER TABLE CLIENT_YEAR_EXPOSURE DROP ALL ROW ACCESS POLICIES;

CREATE OR REPLACE ROW ACCESS POLICY CLIENT_ISOLATION_POLICY
AS (row_client_id VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DEEPKI_INTERNAL_ANALYST')
    OR EXISTS (
        SELECT 1
        FROM CUSTOM_DEMOS.DEEPKI.TENANT_ROLE_MAP m
        WHERE m.role_name = CURRENT_ROLE()
          AND m.client_id = row_client_id
    )
COMMENT = 'Client-level isolation. Tenant roles see only their own client; unmapped roles see nothing.';

ALTER TABLE DIM_ASSET
    ADD ROW ACCESS POLICY CLIENT_ISOLATION_POLICY ON (client_id);
ALTER TABLE DIM_CLIENT
    ADD ROW ACCESS POLICY CLIENT_ISOLATION_POLICY ON (client_id);
ALTER TABLE CLIENT_YEAR_EXPOSURE
    ADD ROW ACCESS POLICY CLIENT_ISOLATION_POLICY ON (client_id);

-- ASSET_YEAR_PERFORMANCE and FACT_ENERGY_MONTHLY have no client_id column
-- of their own. Rather than denormalise one in purely to satisfy the
-- policy, they inherit isolation through the join to DIM_ASSET, which the
-- policy already protects. Worth stating out loud in the room, because a
-- data architect will ask: any query that reaches asset-level performance
-- must pass through DIM_ASSET to resolve the client, and that hop is
-- filtered. The semantic view enforces the same path.

-- The demo user needs all three roles so the presenter can switch between
-- them live. In production a tenant role would be granted only to that
-- tenant's users, and never to a Deepki employee.
GRANT ROLE DEEPKI_TENANT_RHENUS    TO USER AI_USER;
GRANT ROLE DEEPKI_TENANT_VANEAU    TO USER AI_USER;
GRANT ROLE DEEPKI_INTERNAL_ANALYST TO USER AI_USER;

-- ---------------------------------------------------------------------
-- Proof
-- ---------------------------------------------------------------------

-- Deepki internal staff: the whole book.
USE ROLE DEEPKI_INTERNAL_ANALYST;
USE WAREHOUSE COMPUTE_WH;
SELECT 'DEEPKI_INTERNAL_ANALYST' AS acting_role,
       COUNT(*)                  AS clients_visible,
       ROUND(SUM(stranded_m2))   AS stranded_m2_visible
FROM CUSTOM_DEMOS.DEEPKI.CLIENT_YEAR_EXPOSURE
WHERE reporting_year = 2025;

-- The Rhenus energy manager: one client, their own.
USE ROLE DEEPKI_TENANT_RHENUS;
SELECT 'DEEPKI_TENANT_RHENUS' AS acting_role,
       COUNT(*)               AS clients_visible,
       ROUND(SUM(stranded_m2)) AS stranded_m2_visible
FROM CUSTOM_DEMOS.DEEPKI.CLIENT_YEAR_EXPOSURE
WHERE reporting_year = 2025;

-- The Vaneau energy manager: a different single client.
USE ROLE DEEPKI_TENANT_VANEAU;
SELECT 'DEEPKI_TENANT_VANEAU' AS acting_role,
       COUNT(*)               AS clients_visible,
       ROUND(SUM(stranded_m2)) AS stranded_m2_visible
FROM CUSTOM_DEMOS.DEEPKI.CLIENT_YEAR_EXPOSURE
WHERE reporting_year = 2025;

-- Asset-level inheritance: the same tenant role cannot see another
-- client's assets even though ASSET_YEAR_PERFORMANCE carries no client_id.
SELECT 'DEEPKI_TENANT_VANEAU' AS acting_role,
       COUNT(DISTINCT a.client_id) AS clients_visible,
       COUNT(*)                    AS asset_years_visible
FROM CUSTOM_DEMOS.DEEPKI.ASSET_YEAR_PERFORMANCE p
JOIN CUSTOM_DEMOS.DEEPKI.DIM_ASSET a ON a.asset_id = p.asset_id
WHERE p.reading_year = 2025;

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------
-- To remove the policy (for example if it interferes with a rehearsal):
--
--   ALTER TABLE DIM_ASSET            DROP ROW ACCESS POLICY CLIENT_ISOLATION_POLICY;
--   ALTER TABLE DIM_CLIENT           DROP ROW ACCESS POLICY CLIENT_ISOLATION_POLICY;
--   ALTER TABLE CLIENT_YEAR_EXPOSURE DROP ROW ACCESS POLICY CLIENT_ISOLATION_POLICY;
-- ---------------------------------------------------------------------
