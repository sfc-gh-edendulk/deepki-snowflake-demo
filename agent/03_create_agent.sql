-- =====================================================================
-- Deepki demo — Cortex Search service and Cortex Agent
--
-- The agent gets two tools on purpose:
--   analyst  -> the numbers, from the semantic view
--   search   -> the site audit notes, which is the unstructured context
--               Deepki holds but described as barely exploited
--
-- Act 3 recommendations should be grounded in the retrofit catalogue and
-- the audit notes rather than invented, which is what the second tool buys.
-- =====================================================================

USE SCHEMA CUSTOM_DEMOS.DEEPKI;

-- ---------------------------------------------------------------------
-- Searchable corpus: audit notes plus the retrofit catalogue, so one
-- service covers both "what did the auditor find" and "what should we do".
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW ESG_KNOWLEDGE_CORPUS AS
SELECT
    n.note_id                                   AS doc_id,
    n.note_title                                AS doc_title,
    'Site audit'                                AS doc_type,
    n.asset_id                                  AS related_asset_id,
    a.client_id                                 AS related_client_id,
    n.note_date                                 AS doc_date,
    n.auditor_firm                              AS doc_source,
    n.note_title || '. ' || n.note_text         AS doc_text
FROM ASSET_AUDIT_NOTE n
LEFT JOIN DIM_ASSET a ON a.asset_id = n.asset_id
UNION ALL
SELECT
    r.action_id,
    r.action_name,
    'Retrofit action',
    NULL,
    NULL,
    DATE '2026-01-01',
    'Deepki retrofit catalogue',
    r.action_name || ' (' || r.action_category || '). Applies to sectors: '
      || r.applies_to_sector || '. Applies to heating systems: ' || r.applies_to_heating
      || '. Capex ' || r.capex_eur_per_m2::VARCHAR || ' EUR per square metre. Energy saving '
      || r.energy_saving_pct::VARCHAR || ' percent. Carbon saving '
      || r.carbon_saving_pct::VARCHAR || ' percent. Simple payback '
      || r.payback_years::VARCHAR || ' years. Disruption level ' || r.disruption_level
      || '. ' || r.action_description
FROM DIM_RETROFIT_ACTION r;

CREATE OR REPLACE CORTEX SEARCH SERVICE DEEPKI_ESG_KNOWLEDGE_SEARCH
  ON doc_text
  ATTRIBUTES doc_id, doc_title, doc_type, related_asset_id, related_client_id, doc_source
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Site audit notes and the retrofit action catalogue. Grounds recommendations in real documents.'
  AS SELECT doc_id, doc_title, doc_type, related_asset_id, related_client_id,
            doc_date, doc_source, doc_text
     FROM ESG_KNOWLEDGE_CORPUS;

-- ---------------------------------------------------------------------
-- The agent
--
-- CREATE AGENT takes a JSON specification block, not DDL clauses. If this
-- ever needs reshaping, run DESCRIBE AGENT on a working agent and copy the
-- returned agent_spec.
-- ---------------------------------------------------------------------
CREATE OR REPLACE AGENT CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_AGENT
WITH PROFILE='{"display_name":"Deepki Portfolio Copilot"}'
COMMENT = 'Deepki demo agent: portfolio pathway exposure, root cause, and grounded retrofit recommendations.'
FROM SPECIFICATION $$
{
  "models": { "orchestration": "claude-sonnet-4-6" },
  "instructions": {
    "response": "You are a portfolio sustainability analyst for real estate. Answer in English, concisely, and always state the unit and the reporting year for any figure you give. Use square metres for area, kWh for energy and kgCO2e for carbon. When you report a share, give the absolute number alongside it. Never present a market-based or tariff-based measure as if it reduced physical emissions. If a figure rests on estimated invoices or incomplete meter data, say so rather than presenting it as measured. When a question is about a specific client or asset, always name the responsible energy manager and give their email address so the user can act on the answer.",
    "orchestration": "Use the analyst tool for anything numeric: floor area, energy, carbon, intensity, pathway gaps, stranded area, subscription value. Choose intensity carefully by sector. For Office, Retail and Logistics use energy intensity per square metre. For Nursing home, Residential and Hotel prefer energy intensity per occupied room, because floor area alone misrepresents assets where the occupied unit is the thing being serviced; mention that you have done this. When a question combines pathway exposure with subscription revenue, use the client exposure entity rather than trying to join asset-level performance to client-level value. Use the search tool for site audit findings, for what a retrofit action involves, and for anything about recommendations, payback or capex. When recommending actions, take them from the retrofit catalogue rather than proposing measures from general knowledge, and sequence them: cheap no-disruption measures and hydraulic balancing first, then the heat source replacement, because balancing is a prerequisite for a low flow temperature system. Default to reporting year 2025 unless the user asks for another period.",
    "sample_questions": [
      { "question": "How much floor area is off its CRREM pathway in 2025, and how much subscription revenue sits with the most exposed clients?" },
      { "question": "Which client drives the largest share of stranded floor area, and what is the pattern by sector and heating system?" },
      { "question": "What retrofit actions do you recommend for Rhenus Immobilien's five worst assets, and who should I contact?" },
      { "question": "For our nursing homes, show energy intensity per occupied room and compare it with the office portfolio." },
      { "question": "How much of the 2025 consumption rests on estimated invoices or incomplete meter data?" }
    ]
  },
  "orchestration": { "budget": { "seconds": 120, "tokens": 32000 } },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "portfolio_analyst",
        "description": "Energy, carbon, CRREM pathway performance and client subscription exposure across all monitored assets. Use for every numeric question."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "esg_knowledge",
        "description": "Site audit notes from on-site surveys, and the curated retrofit action catalogue with capex, savings and payback. Use for qualitative findings and for grounding any recommendation."
      }
    }
  ],
  "tool_resources": {
    "portfolio_analyst": {
      "semantic_view": "CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_SV",
      "execution_environment": { "type": "warehouse", "warehouse": "COMPUTE_WH", "query_timeout": 90 }
    },
    "esg_knowledge": {
      "search_service": "CUSTOM_DEMOS.DEEPKI.DEEPKI_ESG_KNOWLEDGE_SEARCH",
      "title_column": "doc_title",
      "id_column": "doc_id",
      "max_results": 6
    }
  }
}
$$;

SHOW AGENTS IN SCHEMA CUSTOM_DEMOS.DEEPKI;
