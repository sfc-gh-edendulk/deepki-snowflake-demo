-- =====================================================================
-- Deepki demo — gold layer and semantic view
--
-- Why a gold asset-year table exists rather than pushing everything into
-- the semantic view: "is this asset off its pathway" is an
-- aggregate-then-compare (sum a year of carbon, divide by floor area,
-- compare against a threshold that varies by country, sector and year).
-- Expressing that inside a semantic metric is fragile. Materialising it at
-- asset-year grain makes every downstream metric a plain SUM, which is
-- what Cortex Analyst is reliable at.
-- =====================================================================

USE SCHEMA CUSTOM_DEMOS.DEEPKI;

CREATE OR REPLACE TABLE ASSET_YEAR_PERFORMANCE (
    asset_year_id         VARCHAR(40)  PRIMARY KEY,
    asset_id              VARCHAR(30)  NOT NULL,
    reading_year          NUMBER(4,0)  NOT NULL,
    floor_area_m2         NUMBER(12,2) NOT NULL,
    occupied_units        NUMBER(8,0),
    energy_kwh            NUMBER(16,2) NOT NULL,
    energy_cost_eur       NUMBER(14,2) NOT NULL,
    co2e_kg               NUMBER(16,2) NOT NULL,
    kwh_per_m2            NUMBER(12,2) NOT NULL,
    kwh_per_occupied_unit NUMBER(12,2),
    co2e_kg_per_m2        NUMBER(12,2) NOT NULL,
    threshold_kgco2e_per_m2 NUMBER(10,2) NOT NULL,
    pathway_gap_kgco2e_per_m2 NUMBER(10,2) NOT NULL,
    is_off_pathway        BOOLEAN      NOT NULL,
    stranded_floor_area_m2 NUMBER(12,2) NOT NULL,
    months_reported       NUMBER(3,0)  NOT NULL,
    estimated_month_count NUMBER(3,0)  NOT NULL,
    avg_data_completeness_pct NUMBER(5,2) NOT NULL
)
COMMENT = 'Asset-year performance against the CRREM pathway. One row per asset per reporting year.';

INSERT INTO ASSET_YEAR_PERFORMANCE
WITH annual AS (
    SELECT
        f.asset_id,
        f.reading_year,
        a.floor_area_m2,
        a.occupied_units,
        a.asset_country,
        a.asset_sector,
        SUM(f.energy_kwh)                                AS energy_kwh,
        SUM(f.energy_cost_eur)                           AS energy_cost_eur,
        SUM(f.co2e_kg)                                   AS co2e_kg,
        COUNT(*)                                         AS months_reported,
        SUM(CASE WHEN f.is_estimated THEN 1 ELSE 0 END)  AS estimated_month_count,
        AVG(f.data_completeness_pct)                     AS avg_completeness
    FROM   FACT_ENERGY_MONTHLY f
    JOIN   DIM_ASSET a ON a.asset_id = f.asset_id
    GROUP  BY 1, 2, 3, 4, 5, 6
)
SELECT
    an.asset_id || '-' || an.reading_year::VARCHAR                AS asset_year_id,
    an.asset_id,
    an.reading_year,
    an.floor_area_m2,
    an.occupied_units,
    ROUND(an.energy_kwh, 2),
    ROUND(an.energy_cost_eur, 2),
    ROUND(an.co2e_kg, 2),
    ROUND(an.energy_kwh / an.floor_area_m2, 2)                    AS kwh_per_m2,
    -- Only meaningful for sectors that track occupied units. This is the
    -- second intensity metric Deepki asked for: nursing homes and
    -- residential are judged per occupied room, not per square metre.
    ROUND(an.energy_kwh / NULLIF(an.occupied_units, 0), 2)        AS kwh_per_occupied_unit,
    ROUND(an.co2e_kg / an.floor_area_m2, 2)                       AS co2e_kg_per_m2,
    p.threshold_kgco2e_per_m2,
    ROUND(an.co2e_kg / an.floor_area_m2 - p.threshold_kgco2e_per_m2, 2)
                                                                  AS pathway_gap_kgco2e_per_m2,
    (an.co2e_kg / an.floor_area_m2) > p.threshold_kgco2e_per_m2    AS is_off_pathway,
    -- Pre-resolved so "stranded floor area" is a plain SUM downstream.
    CASE WHEN (an.co2e_kg / an.floor_area_m2) > p.threshold_kgco2e_per_m2
         THEN an.floor_area_m2 ELSE 0 END                          AS stranded_floor_area_m2,
    an.months_reported,
    an.estimated_month_count,
    ROUND(an.avg_completeness, 2)
FROM annual an
JOIN DIM_CRREM_PATHWAY p
     ON  p.pathway_country = an.asset_country
     AND p.pathway_sector  = an.asset_sector
     AND p.pathway_year    = an.reading_year;


-- ---------------------------------------------------------------------
-- Client-year exposure (gold)
--
-- Exists because the headline question mixes two grains: stranded floor
-- area (asset-year) and subscription value (client). Asking the semantic
-- view to combine them directly fails with a granularity error, and
-- denormalising ACV onto the asset-year table would multiply it by the
-- asset count. One row per client per year resolves both problems.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CLIENT_YEAR_EXPOSURE (
    client_year_id       VARCHAR(40)  PRIMARY KEY,
    client_id            VARCHAR(10)  NOT NULL,
    reporting_year       NUMBER(4,0)  NOT NULL,
    monitored_m2         NUMBER(14,2) NOT NULL,
    stranded_m2          NUMBER(14,2) NOT NULL,
    stranded_share_pct   NUMBER(5,2)  NOT NULL,
    total_assets         NUMBER(6,0)  NOT NULL,
    off_pathway_assets   NUMBER(6,0)  NOT NULL,
    annual_energy_kwh    NUMBER(18,2) NOT NULL,
    annual_co2e_kg       NUMBER(18,2) NOT NULL,
    annual_energy_cost   NUMBER(16,2) NOT NULL,
    subscription_acv_eur NUMBER(12,0) NOT NULL,
    months_to_renewal    NUMBER(6,0)  NOT NULL
)
COMMENT = 'One row per client per reporting year: pathway exposure alongside the subscription value it puts at risk.';

INSERT INTO CLIENT_YEAR_EXPOSURE
SELECT
    a.client_id || '-' || p.reading_year::VARCHAR,
    a.client_id,
    p.reading_year,
    ROUND(SUM(p.floor_area_m2), 2),
    ROUND(SUM(p.stranded_floor_area_m2), 2),
    ROUND(100 * SUM(p.stranded_floor_area_m2) / NULLIF(SUM(p.floor_area_m2), 0), 2),
    COUNT(*),
    SUM(CASE WHEN p.is_off_pathway THEN 1 ELSE 0 END),
    ROUND(SUM(p.energy_kwh), 2),
    ROUND(SUM(p.co2e_kg), 2),
    ROUND(SUM(p.energy_cost_eur), 2),
    MAX(c.subscription_acv_eur),
    DATEDIFF(month, DATE '2026-09-03', MAX(c.renewal_date))
FROM ASSET_YEAR_PERFORMANCE p
JOIN DIM_ASSET  a ON a.asset_id  = p.asset_id
JOIN DIM_CLIENT c ON c.client_id = a.client_id
GROUP BY a.client_id, p.reading_year;

-- ---------------------------------------------------------------------
-- Semantic view
--
-- Note on syntax: inside FACTS and DIMENSIONS the logical name comes
-- first and the real column follows AS, which is the reverse of ordinary
-- SQL aliasing. Synonyms are globally unique; duplicates make the model
-- fail silently rather than loudly.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW CUSTOM_DEMOS.DEEPKI.DEEPKI_PORTFOLIO_SV

  TABLES (
    performance AS CUSTOM_DEMOS.DEEPKI.ASSET_YEAR_PERFORMANCE
      PRIMARY KEY (asset_year_id)
      WITH SYNONYMS = ('annual performance', 'pathway performance', 'yearly asset performance')
      COMMENT = 'One row per asset per reporting year, with carbon intensity measured against the CRREM pathway threshold.',

    monthly AS CUSTOM_DEMOS.DEEPKI.FACT_ENERGY_MONTHLY
      PRIMARY KEY (energy_fact_id)
      WITH SYNONYMS = ('monthly consumption', 'monthly energy', 'energy timeline')
      COMMENT = 'Monthly energy and carbon per asset. Use for trends and seasonality.',

    asset AS CUSTOM_DEMOS.DEEPKI.DIM_ASSET
      PRIMARY KEY (asset_id)
      WITH SYNONYMS = ('building', 'property', 'site')
      COMMENT = 'The building being monitored, harmonised from the client asset register.',

    client AS CUSTOM_DEMOS.DEEPKI.DIM_CLIENT
      PRIMARY KEY (client_id)
      WITH SYNONYMS = ('customer', 'portfolio owner', 'subscriber')
      COMMENT = 'The Deepki client that owns or manages the portfolio.',

    exposure AS CUSTOM_DEMOS.DEEPKI.CLIENT_YEAR_EXPOSURE
      PRIMARY KEY (client_year_id)
      WITH SYNONYMS = ('client exposure', 'portfolio exposure', 'commercial exposure')
      COMMENT = 'Per client per year: stranded area next to the subscription value it puts at risk. Use this when a question combines pathway exposure with revenue.',

    retrofit AS CUSTOM_DEMOS.DEEPKI.DIM_RETROFIT_ACTION
      PRIMARY KEY (action_id)
      WITH SYNONYMS = ('retrofit measure', 'improvement action', 'capex measure')
      COMMENT = 'Curated catalogue of retrofit actions with capex, savings and payback.'
  )

  RELATIONSHIPS (
    performance_to_asset AS performance (asset_id)  REFERENCES asset  (asset_id),
    monthly_to_asset     AS monthly     (asset_id)  REFERENCES asset  (asset_id),
    asset_to_client      AS asset       (client_id) REFERENCES client (client_id),
    exposure_to_client   AS exposure    (client_id) REFERENCES client (client_id)
  )

  FACTS (
    performance.annual_energy_kwh AS energy_kwh
      COMMENT = 'Annual delivered energy for the asset, in kWh.',
    performance.annual_energy_cost AS energy_cost_eur
      COMMENT = 'Annual energy spend for the asset, in EUR.',
    performance.annual_co2e_kg AS co2e_kg
      COMMENT = 'Annual location-based carbon emissions for the asset, in kgCO2e.',
    performance.asset_floor_area AS floor_area_m2
      COMMENT = 'Lettable floor area of the asset in square metres.',
    performance.asset_occupied_units AS occupied_units
      COMMENT = 'Occupied rooms or dwellings. Populated only for nursing home, residential and hotel assets.',
    performance.stranded_area AS stranded_floor_area_m2
      COMMENT = 'Floor area counted as stranded: equals the asset floor area when the asset is above its pathway threshold, otherwise zero.',
    performance.pathway_gap AS pathway_gap_kgco2e_per_m2
      COMMENT = 'Carbon intensity minus the pathway threshold. Positive means the asset is off pathway.',
    performance.pathway_threshold AS threshold_kgco2e_per_m2
      COMMENT = 'The CRREM pathway threshold applying to this asset country, sector and year.',
    performance.estimated_months AS estimated_month_count
      COMMENT = 'Number of months in the year where consumption came from a supplier estimate rather than a real reading.',
    performance.completeness AS avg_data_completeness_pct
      COMMENT = 'Average share of expected smart meter readings actually received. Zero means the asset is not metered at all.',
    monthly.month_energy_kwh AS energy_kwh
      COMMENT = 'Delivered energy for one asset in one month, in kWh.',
    monthly.month_co2e_kg AS co2e_kg
      COMMENT = 'Carbon emissions for one asset in one month, in kgCO2e.',
    monthly.month_energy_cost AS energy_cost_eur
      COMMENT = 'Energy spend for one asset in one month, in EUR.',
    monthly.month_fossil_share AS fossil_share_pct
      COMMENT = 'Share of the month energy delivered by gas or heating oil.',
    exposure.exposed_acv AS subscription_acv_eur
      COMMENT = 'Subscription value of the client, at client-year grain so it can be combined with pathway exposure.',
    exposure.exposure_stranded_area AS stranded_m2
      COMMENT = 'Stranded floor area for this client in this year, in square metres.',
    exposure.exposure_monitored_area AS monitored_m2
      COMMENT = 'Total monitored floor area for this client in this year, in square metres.',
    exposure.exposure_off_pathway_assets AS off_pathway_assets
      COMMENT = 'Number of the client assets above their pathway threshold.',
    exposure.exposure_total_assets AS total_assets
      COMMENT = 'Number of assets the client has under monitoring.',
    exposure.renewal_horizon AS months_to_renewal
      COMMENT = 'Months from today until the client subscription renews. Negative means already past.',
    client.client_acv AS subscription_acv_eur
      COMMENT = 'Annual contract value of the Deepki subscription for this client, in EUR.',
    client.client_aum AS assets_under_mgmt_eur
      COMMENT = 'Value of real estate the client manages, in EUR.',
    client.client_ticket_count AS support_tickets_12m
      COMMENT = 'Support tickets raised by the client in the last twelve months.',
    retrofit.action_capex AS capex_eur_per_m2
      COMMENT = 'Capital cost of the retrofit action per square metre, in EUR.',
    retrofit.action_energy_saving AS energy_saving_pct
      COMMENT = 'Expected reduction in delivered energy, as a percentage.',
    retrofit.action_carbon_saving AS carbon_saving_pct
      COMMENT = 'Expected reduction in carbon emissions, as a percentage.',
    retrofit.action_payback AS payback_years
      COMMENT = 'Simple payback period of the action, in years.'
  )

  DIMENSIONS (
    exposure.exposure_year AS reporting_year
      WITH SYNONYMS = ('exposure reporting year', 'commercial year')
      COMMENT = 'Calendar year the client exposure figures cover.',
    performance.reporting_year AS reading_year
      WITH SYNONYMS = ('year', 'reporting period')
      COMMENT = 'Calendar year the performance figures cover.',
    performance.off_pathway_flag AS is_off_pathway
      WITH SYNONYMS = ('stranded', 'above threshold', 'off track')
      COMMENT = 'True when the asset carbon intensity exceeds its CRREM pathway threshold for that year.',
    monthly.consumption_month AS reading_month
      WITH SYNONYMS = ('month', 'billing period')
      COMMENT = 'Month the consumption relates to.',
    monthly.estimated_reading_flag AS is_estimated
      WITH SYNONYMS = ('supplier estimate', 'estimated bill')
      COMMENT = 'True when the month consumption came from a supplier estimate rather than a real reading.',
    monthly.metered_flag AS is_metered
      WITH SYNONYMS = ('has smart meter', 'meter installed')
      COMMENT = 'True when the asset has a smart meter feeding this month.',
    asset.building_name AS asset_name
      WITH SYNONYMS = ('property name', 'site name')
      COMMENT = 'Name of the building.',
    asset.building_country AS asset_country
      WITH SYNONYMS = ('country', 'market')
      COMMENT = 'Country the asset sits in. Drives both the pathway threshold and the electricity grid carbon factor.',
    asset.building_city AS asset_city
      WITH SYNONYMS = ('city', 'town')
      COMMENT = 'City the asset sits in.',
    asset.building_sector AS asset_sector
      WITH SYNONYMS = ('property type', 'asset class', 'use type')
      COMMENT = 'Use type: Office, Retail, Logistics, Nursing home, Residential or Hotel.',
    asset.heating_type AS heating_system
      WITH SYNONYMS = ('heating plant', 'heat source')
      COMMENT = 'Heating system installed. Gas boiler and electric resistance are the main drivers of poor performance.',
    asset.energy_rating AS epc_rating
      WITH SYNONYMS = ('EPC', 'energy performance certificate', 'efficiency rating')
      COMMENT = 'Energy performance certificate band, A best to G worst.',
    asset.construction_year AS build_year
      WITH SYNONYMS = ('year built', 'vintage')
      COMMENT = 'Year the asset was built.',
    asset.occupancy_level AS occupancy_rate_pct
      WITH SYNONYMS = ('occupancy', 'let rate')
      COMMENT = 'Occupancy rate as a percentage.',
    client.portfolio_owner AS client_name
      WITH SYNONYMS = ('client', 'customer name', 'account')
      COMMENT = 'Name of the Deepki client.',
    client.owner_country AS client_country
      WITH SYNONYMS = ('client home country', 'headquarters country')
      COMMENT = 'Country the client is headquartered in.',
    client.owner_segment AS client_type
      WITH SYNONYMS = ('client category', 'investor type')
      COMMENT = 'Asset manager, REIT, Pension fund, Insurer or Operator.',
    client.renewal_due AS renewal_date
      WITH SYNONYMS = ('contract renewal', 'subscription end')
      COMMENT = 'Date the Deepki subscription comes up for renewal.',
    client.account_manager AS csm_owner
      WITH SYNONYMS = ('customer success owner', 'CSM')
      COMMENT = 'Deepki customer success manager for the account.',
    client.energy_manager AS energy_manager_name
      WITH SYNONYMS = ('client energy contact', 'sustainability lead')
      COMMENT = 'Named energy manager at the client. This is the person to contact about asset performance.',
    client.energy_manager_address AS energy_manager_email
      WITH SYNONYMS = ('contact email', 'energy manager mail')
      COMMENT = 'Email address of the client energy manager. Use this when asked who to contact.',
    retrofit.measure_name AS action_name
      WITH SYNONYMS = ('retrofit', 'measure', 'intervention')
      COMMENT = 'Name of the retrofit action.',
    retrofit.measure_category AS action_category
      WITH SYNONYMS = ('action family', 'measure group')
      COMMENT = 'Category of the action: Heating, Envelope, Controls, Lighting and so on.',
    retrofit.measure_sector_fit AS applies_to_sector
      WITH SYNONYMS = ('suitable sectors', 'applicable property types')
      COMMENT = 'Sectors the action applies to, or Any.',
    retrofit.measure_heating_fit AS applies_to_heating
      WITH SYNONYMS = ('suitable heating systems', 'applicable heat sources')
      COMMENT = 'Heating systems the action applies to, or Any.',
    retrofit.measure_disruption AS disruption_level
      WITH SYNONYMS = ('tenant disruption', 'works impact')
      COMMENT = 'How disruptive the works are: Low, Medium or High.',
    retrofit.measure_detail AS action_description
      WITH SYNONYMS = ('action notes', 'measure explanation')
      COMMENT = 'Description of what the action involves and when it is appropriate.'
  )

  METRICS (
    performance.total_stranded_area AS SUM(performance.stranded_area)
      WITH SYNONYMS = ('stranded floor area', 'off pathway area', 'area at risk')
      COMMENT = 'Total floor area in square metres sitting above its CRREM pathway threshold.',
    performance.total_monitored_area AS SUM(performance.asset_floor_area)
      WITH SYNONYMS = ('monitored floor area', 'total portfolio area')
      COMMENT = 'Total floor area monitored, in square metres.',
    performance.stranded_area_share AS
        SUM(performance.stranded_area) / NULLIF(SUM(performance.asset_floor_area), 0) * 100
      WITH SYNONYMS = ('percent stranded', 'share off pathway')
      COMMENT = 'Stranded floor area as a percentage of monitored floor area.',
    performance.off_pathway_asset_count AS
        COUNT(DISTINCT CASE WHEN performance.off_pathway_flag THEN performance.asset_id END)
      WITH SYNONYMS = ('number of stranded assets', 'count off pathway')
      COMMENT = 'Number of distinct assets above their pathway threshold.',
    performance.total_annual_energy AS SUM(performance.annual_energy_kwh)
      WITH SYNONYMS = ('annual consumption', 'total kWh')
      COMMENT = 'Total delivered energy in kWh.',
    performance.total_annual_carbon AS SUM(performance.annual_co2e_kg)
      WITH SYNONYMS = ('total emissions', 'total carbon')
      COMMENT = 'Total location-based carbon emissions in kgCO2e.',
    performance.total_annual_energy_spend AS SUM(performance.annual_energy_cost)
      WITH SYNONYMS = ('energy bill', 'total energy cost')
      COMMENT = 'Total energy spend in EUR.',
    -- The two intensity metrics that let one model serve very different
    -- client types. Offices are judged per square metre; nursing homes,
    -- residential and hotels are judged per occupied room.
    performance.energy_intensity_per_sqm AS
        SUM(performance.annual_energy_kwh) / NULLIF(SUM(performance.asset_floor_area), 0)
      WITH SYNONYMS = ('kWh per square metre', 'energy intensity by area')
      COMMENT = 'Delivered energy per square metre, in kWh/m2. The standard measure for offices, retail and logistics.',
    performance.energy_intensity_per_occupied_unit AS
        SUM(performance.annual_energy_kwh) / NULLIF(SUM(performance.asset_occupied_units), 0)
      WITH SYNONYMS = ('kWh per occupied room', 'energy per bed', 'intensity per dwelling')
      COMMENT = 'Delivered energy per occupied room or dwelling, in kWh. The right measure for nursing homes, residential and hotels, where floor area alone misrepresents performance.',
    performance.carbon_intensity_per_sqm AS
        SUM(performance.annual_co2e_kg) / NULLIF(SUM(performance.asset_floor_area), 0)
      WITH SYNONYMS = ('kgCO2e per square metre', 'carbon intensity by area')
      COMMENT = 'Carbon emissions per square metre, in kgCO2e/m2. This is the figure compared against the pathway threshold.',
    performance.avg_pathway_gap AS AVG(performance.pathway_gap)
      WITH SYNONYMS = ('average gap to pathway', 'mean overshoot')
      COMMENT = 'Average distance above or below the pathway threshold, in kgCO2e/m2.',
    performance.avg_data_quality AS AVG(performance.completeness)
      WITH SYNONYMS = ('average meter coverage', 'data completeness')
      COMMENT = 'Average share of expected meter readings received. Low values mean the figures rest on invoices rather than measurement.',
    performance.estimated_month_total AS SUM(performance.estimated_months)
      WITH SYNONYMS = ('estimated billing months', 'number of estimated months')
      COMMENT = 'Count of asset-months where consumption was a supplier estimate.',
    exposure.subscription_value_at_risk AS SUM(exposure.exposed_acv)
      WITH SYNONYMS = ('revenue at risk', 'ACV at risk', 'subscription value exposed')
      COMMENT = 'Total subscription value of the clients in scope, in EUR. Combine with stranded area to size the commercial impact of a performance problem.',
    exposure.client_stranded_area AS SUM(exposure.exposure_stranded_area)
      WITH SYNONYMS = ('stranded area by client', 'client off pathway area')
      COMMENT = 'Stranded floor area aggregated at client level, in square metres.',
    exposure.client_stranded_share AS
        SUM(exposure.exposure_stranded_area) / NULLIF(SUM(exposure.exposure_monitored_area), 0) * 100
      WITH SYNONYMS = ('client percent stranded', 'share of client portfolio stranded')
      COMMENT = 'Share of the client monitored area that is off pathway, as a percentage.',
    client.total_subscription_value AS SUM(client.client_acv)
      WITH SYNONYMS = ('total ACV', 'subscription revenue', 'contract value')
      COMMENT = 'Total annual contract value in EUR. Use this to size the commercial exposure behind a performance problem.',
    client.total_assets_under_management AS SUM(client.client_aum)
      WITH SYNONYMS = ('total AUM', 'assets under management')
      COMMENT = 'Total value of real estate managed by the clients in scope, in EUR.',
    client.total_support_tickets AS SUM(client.client_ticket_count)
      WITH SYNONYMS = ('support ticket volume', 'ticket count')
      COMMENT = 'Support tickets raised in the last twelve months.',
    monthly.monthly_energy AS SUM(monthly.month_energy_kwh)
      WITH SYNONYMS = ('energy by month', 'monthly kWh')
      COMMENT = 'Delivered energy in kWh, for month-level trends.',
    monthly.monthly_carbon AS SUM(monthly.month_co2e_kg)
      WITH SYNONYMS = ('emissions by month', 'monthly carbon')
      COMMENT = 'Carbon emissions in kgCO2e, for month-level trends.',
    monthly.avg_fossil_share AS AVG(monthly.month_fossil_share)
      WITH SYNONYMS = ('fossil dependency', 'share of fossil energy')
      COMMENT = 'Average share of energy delivered by gas or heating oil, as a percentage.',
    retrofit.avg_action_payback AS AVG(retrofit.action_payback)
      WITH SYNONYMS = ('typical payback', 'mean payback period')
      COMMENT = 'Average simple payback of the actions in scope, in years.',
    retrofit.avg_action_capex AS AVG(retrofit.action_capex)
      WITH SYNONYMS = ('typical capex', 'mean capital cost')
      COMMENT = 'Average capital cost per square metre of the actions in scope, in EUR.',
    retrofit.max_carbon_saving AS MAX(retrofit.action_carbon_saving)
      WITH SYNONYMS = ('best carbon saving', 'highest emissions reduction')
      COMMENT = 'Largest carbon saving available among the actions in scope, as a percentage.'
  )

  COMMENT = 'Deepki portfolio intelligence: energy, carbon and CRREM pathway performance across monitored real estate, joined to client subscription data and a retrofit action catalogue.';
