-- =====================================================================
-- Data engineering demo — orchestration with Tasks and a Task Graph
--
-- Romain's exact question: "on utilise Prefect pour le moment pour faire
-- la partie orchestration. Est-ce que vous avez des features comme ça
-- pour aider?" Elizabeth's answer: keep Prefect if you want, or replace
-- or complement it with Tasks and Task Graphs. This is that feature,
-- built as a three-node DAG over the two ingestion paths and the two
-- transformation paths already in this module.
--
--   DE_TASK_LAND_CHECK (root)
--        |
--        v  AFTER
--   DE_TASK_RUN_PYTHON_HARMONISE  (calls the Snowpark procedure from 04)
--        |
--        v  AFTER
--   DE_TASK_REFRESH_DYNAMIC_TABLE (refreshes the Dynamic Table from 03)
--
-- Both downstream tasks depend on the root, and the graph runs on
-- COMPUTE_WH — no new warehouse, consistent with the rest of this repo.
-- =====================================================================

USE SCHEMA CUSTOM_DEMOS.DEEPKI;

CREATE OR REPLACE TASK DE_TASK_LAND_CHECK
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 4 * * * Europe/Paris'
  COMMENT = 'Root of the graph. In production this is where you would check a Stream on the raw landing tables for new documents/files before doing any work.'
AS
  SELECT COUNT(*) FROM DE_RAW_MONGO_ASSET_DOCUMENTS;

CREATE OR REPLACE TASK DE_TASK_RUN_PYTHON_HARMONISE
  WAREHOUSE = COMPUTE_WH
  COMMENT = 'Calls the pure-Python harmonisation procedure from 04. This is the node a Python-only team would own.'
  AFTER DE_TASK_LAND_CHECK
AS
  CALL DE_BUILD_ASSET_HARMONISED();

CREATE OR REPLACE TASK DE_TASK_REFRESH_DYNAMIC_TABLE
  WAREHOUSE = COMPUTE_WH
  COMMENT = 'Refreshes the SQL-first Dynamic Table from 03. Runs in parallel with the Python task above, not after it — both read the same landing tables independently.'
  AFTER DE_TASK_LAND_CHECK
AS
  ALTER DYNAMIC TABLE DE_DT_ASSET_HARMONISED REFRESH;

-- Tasks are created suspended by default. A graph must be resumed leaf-first,
-- i.e. children before the root, or the root will fire into children that
-- aren't listening yet.
ALTER TASK DE_TASK_RUN_PYTHON_HARMONISE RESUME;
ALTER TASK DE_TASK_REFRESH_DYNAMIC_TABLE RESUME;
ALTER TASK DE_TASK_LAND_CHECK RESUME;

-- Prove the graph runs end to end without waiting for the 04:00 schedule.
EXECUTE TASK DE_TASK_LAND_CHECK;

-- Task execution is asynchronous; give the graph a few seconds to
-- complete both branches before checking history.
CALL SYSTEM$WAIT(20);

SELECT name, state, scheduled_time, completed_time, error_code
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    TASK_NAME => 'DE_TASK_LAND_CHECK',
    SCHEDULED_TIME_RANGE_START => DATEADD('minute', -5, CURRENT_TIMESTAMP())
))
ORDER BY scheduled_time DESC
LIMIT 5;

SELECT name, state, scheduled_time, completed_time, error_code
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    TASK_NAME => 'DE_TASK_RUN_PYTHON_HARMONISE',
    SCHEDULED_TIME_RANGE_START => DATEADD('minute', -5, CURRENT_TIMESTAMP())
))
ORDER BY scheduled_time DESC
LIMIT 5;

SELECT name, state, scheduled_time, completed_time, error_code
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    TASK_NAME => 'DE_TASK_REFRESH_DYNAMIC_TABLE',
    SCHEDULED_TIME_RANGE_START => DATEADD('minute', -5, CURRENT_TIMESTAMP())
))
ORDER BY scheduled_time DESC
LIMIT 5;

-- Suspend everything once verified. A demo account should not leave a
-- cron running against nobody's data at 4am forever.
ALTER TASK DE_TASK_LAND_CHECK SUSPEND;
ALTER TASK DE_TASK_RUN_PYTHON_HARMONISE SUSPEND;
ALTER TASK DE_TASK_REFRESH_DYNAMIC_TABLE SUSPEND;

SHOW TASKS LIKE 'DE_TASK%';
