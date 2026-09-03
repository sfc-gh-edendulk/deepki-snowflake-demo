-- =====================================================================
-- Deepki demo — source domains and harmonised model
-- Target: CUSTOM_DEMOS.DEEPKI on your own Snowflake account
--
-- Four source domains, deliberately kept separate, because the whole
-- argument of the demo is that the headline question cannot be answered
-- from any single one of them:
--
--   A  metering + utility billing   -> RAW_METER_READINGS, RAW_UTILITY_INVOICES
--   B  the client's asset system    -> RAW_ASSET_REGISTER
--   C  external regulatory data     -> DIM_CRREM_PATHWAY
--   D  Deepki's commercial system   -> DIM_CLIENT
--
-- All synthetic data is deterministic. The figures quoted in
-- DEMO_SCRIPT.md and DEMO_ARTIFACT.html depend on it staying that way.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS CUSTOM_DEMOS;
CREATE SCHEMA IF NOT EXISTS CUSTOM_DEMOS.DEEPKI;
USE SCHEMA CUSTOM_DEMOS.DEEPKI;

-- ---------------------------------------------------------------------
-- Domain D — Deepki's own commercial system
-- Carries the action field: energy_manager_email. Act 3 reads it verbatim.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_CLIENT (
    client_id             VARCHAR(10)    PRIMARY KEY,
    client_name           VARCHAR(120)   NOT NULL,
    client_country        VARCHAR(40)    NOT NULL,
    client_type           VARCHAR(40)    NOT NULL, -- Asset manager, REIT, Pension fund, Insurer, Operator
    assets_under_mgmt_eur NUMBER(18,0)   NOT NULL,
    subscription_acv_eur  NUMBER(12,0)   NOT NULL,
    contract_start_date   DATE           NOT NULL,
    renewal_date          DATE           NOT NULL,
    csm_owner             VARCHAR(80)    NOT NULL,
    energy_manager_name   VARCHAR(80)    NOT NULL,
    energy_manager_email  VARCHAR(120)   NOT NULL,
    support_tickets_12m   NUMBER(6,0)    NOT NULL
)
COMMENT = 'Deepki commercial system: subscription, ownership and the energy manager contact.';

INSERT INTO DIM_CLIENT
(client_id, client_name, client_country, client_type, assets_under_mgmt_eur,
 subscription_acv_eur, contract_start_date, renewal_date, csm_owner,
 energy_manager_name, energy_manager_email, support_tickets_12m)
VALUES
-- The three largest clients carry most of the portfolio and most of the risk.
('CL001','Vaneau Asset Management','France','Asset manager',14200000000,412000,'2021-04-01','2027-03-31','Camille Roux','Paul Mercier','paul.mercier@vaneau-am.com',41),
('CL002','Rhenus Immobilien GmbH','Germany','REIT',11800000000,368000,'2020-09-15','2026-09-14','Camille Roux','Andrea Vogt','andrea.vogt@rhenus-immo.de',63),
('CL003','Nordica Pension Real Estate','Sweden','Pension fund',9600000000,295000,'2022-01-10','2027-01-09','Julien Bataille','Erik Lindqvist','erik.lindqvist@nordica-pre.se',22),
('CL004','Bergamo Retail Partners','Italy','Asset manager',6400000000,214000,'2022-06-01','2026-11-30','Julien Bataille','Chiara Rossi','chiara.rossi@bergamoretail.it',37),
('CL005','Meridian Care Estates','United Kingdom','Operator',4900000000,186000,'2021-11-01','2026-10-31','Sofia Almeida','Helen Cartwright','helen.cartwright@meridiancare.co.uk',58),
('CL006','Batignolles Foncière','France','REIT',4300000000,164000,'2023-02-01','2027-01-31','Sofia Almeida','Nicolas Girard','nicolas.girard@batignolles-fonciere.fr',19),
('CL007','Hanseatic Logistik Invest','Germany','Asset manager',3700000000,142000,'2022-04-15','2027-04-14','Camille Roux','Markus Brandt','markus.brandt@hanseatic-li.de',26),
('CL008','Iberia Prime Offices','Spain','REIT',3100000000,128000,'2023-05-01','2026-10-15','Julien Bataille','Lucia Ferrer','lucia.ferrer@iberiaprime.es',31),
('CL009','Amstel Residential Fund','Netherlands','Pension fund',2800000000,116000,'2022-09-01','2027-08-31','Sofia Almeida','Sanne de Wit','sanne.dewit@amstelresidential.nl',14),
('CL010','Helvetia Real Assets','Switzerland','Insurer',2500000000,104000,'2021-07-01','2026-12-31','Camille Roux','Thomas Bühler','thomas.buhler@helvetia-ra.ch',11),
('CL011','Lyon Métropole Patrimoine','France','Asset manager',1900000000,88000,'2023-09-01','2027-08-31','Julien Bataille','Amélie Fournier','amelie.fournier@lyon-patrimoine.fr',23),
('CL012','Baltic Care Homes','Poland','Operator',1600000000,76000,'2023-03-15','2027-03-14','Sofia Almeida','Anna Kowalska','anna.kowalska@balticcare.pl',44),
('CL013','Copenhagen Urban Estates','Denmark','REIT',1400000000,68000,'2024-01-15','2027-01-14','Camille Roux','Mads Jørgensen','mads.jorgensen@cph-urban.dk',9),
('CL014','Provence Hospitality Group','France','Operator',1100000000,58000,'2023-11-01','2026-10-31','Julien Bataille','Sébastien Blanc','sebastien.blanc@provence-hg.fr',29),
('CL015','Vienna Office Trust','Austria','Asset manager',900000000,49000,'2024-04-01','2027-03-31','Sofia Almeida','Katharina Huber','katharina.huber@viennaoffice.at',7);

-- ---------------------------------------------------------------------
-- Domain C — external regulatory data (CRREM decarbonisation pathways)
-- kgCO2e/m2/year thresholds. An asset above its threshold is stranded.
-- Values tighten year on year, and differ by country and sector.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_CRREM_PATHWAY (
    pathway_id              VARCHAR(24)  PRIMARY KEY,
    pathway_country         VARCHAR(40)  NOT NULL,
    pathway_sector          VARCHAR(40)  NOT NULL,
    pathway_year            NUMBER(4,0)  NOT NULL,
    threshold_kgco2e_per_m2 NUMBER(8,2)  NOT NULL,
    grid_carbon_factor      NUMBER(6,4)  NOT NULL -- kgCO2e per kWh of electricity
)
COMMENT = 'CRREM-style decarbonisation pathway thresholds by country, sector and year.';

-- Base intensity per sector, scaled by a country factor, tightened ~6% a year.
INSERT INTO DIM_CRREM_PATHWAY
(pathway_id, pathway_country, pathway_sector, pathway_year,
 threshold_kgco2e_per_m2, grid_carbon_factor)
SELECT
    c.country_code || '-' || s.sector_code || '-' || y.yr           AS pathway_id,
    c.country_name                                                 AS pathway_country,
    s.sector_name                                                  AS pathway_sector,
    y.yr                                                           AS pathway_year,
    ROUND(s.base_threshold * c.country_scale * POWER(0.94, y.yr - 2023), 2)
                                                                   AS threshold_kgco2e_per_m2,
    c.grid_factor                                                  AS grid_carbon_factor
FROM (
    -- Grid carbon factor drives the France-vs-Germany story Deepki publishes
    -- in its own index: same kWh, very different CO2.
    SELECT 'FR' AS country_code, 'France'         AS country_name, 1.00 AS country_scale, 0.0580 AS grid_factor UNION ALL
    SELECT 'DE', 'Germany',        1.30, 0.3660 UNION ALL
    SELECT 'SE', 'Sweden',         0.85, 0.0410 UNION ALL
    SELECT 'IT', 'Italy',          1.15, 0.2570 UNION ALL
    SELECT 'GB', 'United Kingdom', 1.10, 0.2120 UNION ALL
    SELECT 'ES', 'Spain',          1.05, 0.1740 UNION ALL
    SELECT 'NL', 'Netherlands',    1.20, 0.3280 UNION ALL
    SELECT 'CH', 'Switzerland',    0.80, 0.0470 UNION ALL
    SELECT 'PL', 'Poland',         1.40, 0.6570 UNION ALL
    SELECT 'DK', 'Denmark',        0.90, 0.1090 UNION ALL
    SELECT 'AT', 'Austria',        0.95, 0.0910
) c
CROSS JOIN (
    SELECT 'OFF' AS sector_code, 'Office'       AS sector_name, 32.0 AS base_threshold UNION ALL
    SELECT 'RET', 'Retail',       38.0 UNION ALL
    SELECT 'LOG', 'Logistics',    18.0 UNION ALL
    SELECT 'NUR', 'Nursing home', 54.0 UNION ALL
    SELECT 'RES', 'Residential',  26.0 UNION ALL
    SELECT 'HOT', 'Hotel',        46.0
) s
CROSS JOIN (
    SELECT 2023 AS yr UNION ALL SELECT 2024 UNION ALL SELECT 2025 UNION ALL SELECT 2026
) y;

-- ---------------------------------------------------------------------
-- Domain B — the client's asset management system, as delivered
-- Messy on purpose: mixed country spellings, floor area in mixed units,
-- occupancy missing where the sector does not track it. This mirrors what
-- Deepki actually receives, and gives the notebook something real to clean.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW_ASSET_REGISTER (
    source_asset_ref   VARCHAR(30)  PRIMARY KEY,
    source_client_ref  VARCHAR(10)  NOT NULL,
    asset_label        VARCHAR(140) NOT NULL,
    country_raw        VARCHAR(40)  NOT NULL,
    city               VARCHAR(60)  NOT NULL,
    sector_raw         VARCHAR(40)  NOT NULL,
    floor_area_value   NUMBER(12,2) NOT NULL,
    floor_area_unit    VARCHAR(10)  NOT NULL, -- sqm or sqft, as delivered
    occupied_units     NUMBER(8,0),           -- NULL where not tracked
    occupancy_rate_pct NUMBER(5,2),           -- NULL for some feeds
    heating_system     VARCHAR(40)  NOT NULL,
    epc_rating         VARCHAR(4),
    build_year         NUMBER(4,0)  NOT NULL
)
COMMENT = 'Asset register exactly as clients deliver it: inconsistent units and spellings.';

-- 1,200 assets. Everything categorical is derived from the row number, so the
-- spread is deterministic and no sector or country ends up empty.
INSERT INTO RAW_ASSET_REGISTER
(source_asset_ref, source_client_ref, asset_label, country_raw, city, sector_raw,
 floor_area_value, floor_area_unit, occupied_units, occupancy_rate_pct,
 heating_system, epc_rating, build_year)
WITH seq AS (
    SELECT SEQ4() + 1 AS n
    FROM TABLE(GENERATOR(ROWCOUNT => 1200))
),
-- Client allocation is a fixed step function, not a random draw. This is what
-- creates the Pareto concentration the WHY question depends on.
alloc AS (
    SELECT
        n,
        CASE
            WHEN n <=  260 THEN 'CL001'
            WHEN n <=  500 THEN 'CL002'
            WHEN n <=  650 THEN 'CL003'
            WHEN n <=  760 THEN 'CL004'
            WHEN n <=  860 THEN 'CL005'
            WHEN n <=  935 THEN 'CL006'
            WHEN n <=  995 THEN 'CL007'
            WHEN n <= 1050 THEN 'CL008'
            WHEN n <= 1095 THEN 'CL009'
            WHEN n <= 1130 THEN 'CL010'
            WHEN n <= 1158 THEN 'CL011'
            WHEN n <= 1180 THEN 'CL012'
            WHEN n <= 1192 THEN 'CL013'
            WHEN n <= 1197 THEN 'CL014'
            ELSE 'CL015'
        END AS client_id
    FROM seq
),
shaped AS (
    SELECT
        a.n,
        a.client_id,
        c.client_country,
        -- Sector mix varies by client type so the portfolios feel distinct.
        -- Operators skew to nursing homes and hotels, logistics sits with the
        -- logistics specialist, and CL002 gets a heavy nursing-home cluster
        -- because it is the intended WHY answer.
        CASE
            WHEN a.client_id = 'CL002' AND MOD(a.n, 10) < 7 THEN 'Nursing home'
            WHEN a.client_id = 'CL005'                      THEN 'Nursing home'
            WHEN a.client_id = 'CL012'                      THEN 'Nursing home'
            WHEN a.client_id = 'CL007'                      THEN 'Logistics'
            WHEN a.client_id = 'CL014'                      THEN 'Hotel'
            WHEN a.client_id = 'CL009'                      THEN 'Residential'
            WHEN MOD(a.n, 7) = 0                            THEN 'Retail'
            WHEN MOD(a.n, 7) = 1                            THEN 'Logistics'
            WHEN MOD(a.n, 7) = 2                            THEN 'Residential'
            WHEN MOD(a.n, 7) = 3                            THEN 'Hotel'
            ELSE 'Office'
        END AS sector_name,
        -- Floor area is lognormal-ish: a few very large assets, many mid-sized.
        ROUND(
            CASE
                WHEN MOD(a.n, 50) = 0 THEN 42000 + MOD(a.n * 131, 38000)
                WHEN MOD(a.n, 10) = 0 THEN 16000 + MOD(a.n * 79, 14000)
                ELSE 2200 + MOD(a.n * 37, 9800)
            END, 2) AS area_sqm,
        CASE c.client_country
            WHEN 'France'         THEN CASE MOD(ABS(HASH(a.n, 11)), 5) WHEN 0 THEN 'Paris' WHEN 1 THEN 'Lyon' WHEN 2 THEN 'Lille' WHEN 3 THEN 'Bordeaux' ELSE 'Marseille' END
            WHEN 'Germany'        THEN CASE MOD(ABS(HASH(a.n, 11)), 5) WHEN 0 THEN 'Berlin' WHEN 1 THEN 'Munich' WHEN 2 THEN 'Hamburg' WHEN 3 THEN 'Frankfurt' ELSE 'Cologne' END
            WHEN 'Sweden'         THEN CASE MOD(ABS(HASH(a.n, 11)), 3) WHEN 0 THEN 'Stockholm' WHEN 1 THEN 'Gothenburg' ELSE 'Malmo' END
            WHEN 'Italy'          THEN CASE MOD(ABS(HASH(a.n, 11)), 4) WHEN 0 THEN 'Milan' WHEN 1 THEN 'Rome' WHEN 2 THEN 'Turin' ELSE 'Bologna' END
            WHEN 'United Kingdom' THEN CASE MOD(ABS(HASH(a.n, 11)), 4) WHEN 0 THEN 'London' WHEN 1 THEN 'Manchester' WHEN 2 THEN 'Bristol' ELSE 'Leeds' END
            WHEN 'Spain'          THEN CASE MOD(ABS(HASH(a.n, 11)), 3) WHEN 0 THEN 'Madrid' WHEN 1 THEN 'Barcelona' ELSE 'Valencia' END
            WHEN 'Netherlands'    THEN CASE MOD(ABS(HASH(a.n, 11)), 3) WHEN 0 THEN 'Amsterdam' WHEN 1 THEN 'Rotterdam' ELSE 'Utrecht' END
            WHEN 'Switzerland'    THEN CASE MOD(ABS(HASH(a.n, 11)), 3) WHEN 0 THEN 'Zurich' WHEN 1 THEN 'Geneva' ELSE 'Basel' END
            WHEN 'Poland'         THEN CASE MOD(ABS(HASH(a.n, 11)), 3) WHEN 0 THEN 'Warsaw' WHEN 1 THEN 'Krakow' ELSE 'Gdansk' END
            WHEN 'Denmark'        THEN CASE MOD(ABS(HASH(a.n, 11)), 2) WHEN 0 THEN 'Copenhagen' ELSE 'Aarhus' END
            ELSE CASE MOD(ABS(HASH(a.n, 11)), 2) WHEN 0 THEN 'Vienna' ELSE 'Graz' END
        END AS city_name
    FROM alloc a
    JOIN DIM_CLIENT c ON c.client_id = a.client_id
)
SELECT
    'AST-' || LPAD(s.n::VARCHAR, 5, '0')                     AS source_asset_ref,
    s.client_id                                              AS source_client_ref,
    -- Asset labels read like a real register: street-ish name plus city.
    -- Asset labels follow local naming conventions, so a German asset does not
    -- end up with a French name.
    CASE s.client_country
        WHEN 'France' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 6) WHEN 0 THEN 'Le Carré ' WHEN 1 THEN 'Résidence '
                 WHEN 2 THEN 'Domaine ' WHEN 3 THEN 'Quartier '
                 WHEN 4 THEN 'Les Jardins de ' ELSE 'Espace ' END
        WHEN 'Germany' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 6) WHEN 0 THEN 'Haus am ' WHEN 1 THEN 'Seniorenresidenz '
                 WHEN 2 THEN 'Park Carree ' WHEN 3 THEN 'Stadthaus '
                 WHEN 4 THEN 'Am Alten Markt ' ELSE 'Wohnstift ' END
        WHEN 'Italy' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 4) WHEN 0 THEN 'Torre ' WHEN 1 THEN 'Palazzo '
                 WHEN 2 THEN 'Residenza ' ELSE 'Centro ' END
        WHEN 'Spain' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 4) WHEN 0 THEN 'Edificio ' WHEN 1 THEN 'Torre '
                 WHEN 2 THEN 'Residencia ' ELSE 'Plaza ' END
        WHEN 'Sweden' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 3) WHEN 0 THEN 'Kvarteret ' WHEN 1 THEN 'Vardhem ' ELSE 'Huset ' END
        WHEN 'Denmark' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 3) WHEN 0 THEN 'Bygningen ' WHEN 1 THEN 'Plejehjem ' ELSE 'Karreen ' END
        WHEN 'Netherlands' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 3) WHEN 0 THEN 'Het Kwartier ' WHEN 1 THEN 'Woonzorg ' ELSE 'De Hof ' END
        WHEN 'Poland' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 3) WHEN 0 THEN 'Dom Opieki ' WHEN 1 THEN 'Kamienica ' ELSE 'Centrum ' END
        WHEN 'Switzerland' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 3) WHEN 0 THEN 'Haus ' WHEN 1 THEN 'Residenz ' ELSE 'Zentrum ' END
        WHEN 'Austria' THEN
            CASE MOD(ABS(HASH(s.n, 23)), 3) WHEN 0 THEN 'Hof ' WHEN 1 THEN 'Seniorenheim ' ELSE 'Palais ' END
        ELSE
            CASE MOD(ABS(HASH(s.n, 23)), 5) WHEN 0 THEN 'Park House ' WHEN 1 THEN 'The Old '
                 WHEN 2 THEN 'Riverside ' WHEN 3 THEN 'Grange ' ELSE 'Manor ' END
    END || s.city_name || ' ' || LPAD(MOD(ABS(HASH(s.n, 41)), 89)::VARCHAR, 2, '0')
                                                             AS asset_label,
    -- Country spelling is inconsistent on purpose, one feed in three.
    CASE
        WHEN MOD(s.n, 3) = 0 AND s.client_country = 'Germany'        THEN 'DEUTSCHLAND'
        WHEN MOD(s.n, 3) = 0 AND s.client_country = 'France'         THEN 'FR'
        WHEN MOD(s.n, 3) = 0 AND s.client_country = 'United Kingdom' THEN 'UK'
        WHEN MOD(s.n, 3) = 1                                         THEN UPPER(s.client_country)
        ELSE s.client_country
    END                                                      AS country_raw,
    s.city_name                                              AS city,
    -- Sector labels also arrive in variant forms.
    CASE
        WHEN MOD(s.n, 4) = 0 AND s.sector_name = 'Nursing home' THEN 'EHPAD'
        WHEN MOD(s.n, 4) = 0 AND s.sector_name = 'Office'       THEN 'Bureaux'
        WHEN MOD(s.n, 5) = 0                                    THEN UPPER(s.sector_name)
        ELSE s.sector_name
    END                                                      AS sector_raw,
    -- One feed in six reports square feet.
    CASE WHEN MOD(s.n, 6) = 0
         THEN ROUND(s.area_sqm * 10.7639, 2)
         ELSE s.area_sqm
    END                                                      AS floor_area_value,
    CASE WHEN MOD(s.n, 6) = 0 THEN 'sqft' ELSE 'sqm' END     AS floor_area_unit,
    -- Occupied units only exist where the sector tracks them.
    CASE WHEN s.sector_name IN ('Nursing home','Residential','Hotel')
         THEN GREATEST(8, ROUND(s.area_sqm / 42))
         ELSE NULL
    END                                                      AS occupied_units,
    CASE WHEN MOD(s.n, 11) = 0 THEN NULL
         ELSE ROUND(72 + MOD(s.n * 7, 27), 2)
    END                                                      AS occupancy_rate_pct,
    -- Heating system is the WHY drill-down. Gas and electric resistance are
    -- the offenders; CL002's nursing homes are deliberately loaded with them.
    CASE
        WHEN s.client_id = 'CL002' AND s.sector_name = 'Nursing home' AND MOD(s.n, 3) <> 2 THEN 'Gas boiler'
        WHEN s.client_id = 'CL002' AND s.sector_name = 'Nursing home'                       THEN 'Electric resistance'
        WHEN s.client_id IN ('CL005','CL012') AND MOD(s.n, 4) < 3                           THEN 'Gas boiler'
        WHEN MOD(s.n, 9) = 0 THEN 'Electric resistance'
        WHEN MOD(s.n, 9) IN (1,2) THEN 'Gas boiler'
        WHEN MOD(s.n, 9) IN (3,4) THEN 'District heating'
        WHEN MOD(s.n, 9) IN (5,6) THEN 'Heat pump'
        WHEN MOD(s.n, 9) = 7 THEN 'Oil boiler'
        ELSE 'Gas boiler + solar'
    END                                                      AS heating_system,
    -- CL002 acquired a legacy German care portfolio in bulk and inherited its
    -- EPC profile, which is why its ratings skew far worse than the book.
    CASE
        WHEN s.client_id = 'CL002' THEN
            CASE MOD(ABS(HASH(s.n, 37)), 8)
                WHEN 0 THEN 'D' WHEN 1 THEN 'E' WHEN 2 THEN 'E' WHEN 3 THEN 'F'
                WHEN 4 THEN 'F' WHEN 5 THEN 'G' WHEN 6 THEN 'G' ELSE 'F'
            END
        ELSE
            CASE MOD(ABS(HASH(s.n, 37)), 8)
                WHEN 0 THEN 'A' WHEN 1 THEN 'B' WHEN 2 THEN 'C' WHEN 3 THEN 'D'
                WHEN 4 THEN 'E' WHEN 5 THEN 'F' WHEN 6 THEN 'G' ELSE NULL
            END
    END                                                      AS epc_rating,
    1955 + MOD(s.n * 13, 68)                                 AS build_year
FROM shaped s;

-- ---------------------------------------------------------------------
-- Harmonised asset dimension (silver)
-- Resolves the three delivery inconsistencies: country spelling, sector
-- labels, and square feet vs square metres.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_ASSET (
    asset_id           VARCHAR(30)  PRIMARY KEY,
    client_id          VARCHAR(10)  NOT NULL,
    asset_name         VARCHAR(140) NOT NULL,
    asset_country      VARCHAR(40)  NOT NULL,
    asset_city         VARCHAR(60)  NOT NULL,
    asset_sector       VARCHAR(40)  NOT NULL,
    floor_area_m2      NUMBER(12,2) NOT NULL,
    occupied_units     NUMBER(8,0),
    occupancy_rate_pct NUMBER(5,2),
    heating_system     VARCHAR(40)  NOT NULL,
    epc_rating         VARCHAR(4),
    build_year         NUMBER(4,0)  NOT NULL,
    -- Efficiency multiplier derived from EPC. Poor ratings consume more.
    efficiency_factor  NUMBER(5,3)  NOT NULL
)
COMMENT = 'Harmonised asset register: consistent country, sector and floor area in m2.';

INSERT INTO DIM_ASSET
SELECT
    r.source_asset_ref,
    r.source_client_ref,
    r.asset_label,
    -- Country harmonisation
    CASE UPPER(r.country_raw)
        WHEN 'DEUTSCHLAND' THEN 'Germany'
        WHEN 'FR'          THEN 'France'
        WHEN 'UK'          THEN 'United Kingdom'
        ELSE INITCAP(r.country_raw)
    END,
    r.city,
    -- Sector harmonisation
    CASE UPPER(r.sector_raw)
        WHEN 'EHPAD'        THEN 'Nursing home'
        WHEN 'BUREAUX'      THEN 'Office'
        WHEN 'NURSING HOME' THEN 'Nursing home'
        ELSE INITCAP(r.sector_raw)
    END,
    -- Unit harmonisation
    CASE WHEN r.floor_area_unit = 'sqft'
         THEN ROUND(r.floor_area_value / 10.7639, 2)
         ELSE r.floor_area_value
    END,
    r.occupied_units,
    r.occupancy_rate_pct,
    r.heating_system,
    r.epc_rating,
    r.build_year,
    CASE r.epc_rating
        WHEN 'A' THEN 0.60 WHEN 'B' THEN 0.70 WHEN 'C' THEN 0.85
        WHEN 'D' THEN 1.00 WHEN 'E' THEN 1.20 WHEN 'F' THEN 1.45
        WHEN 'G' THEN 1.70 ELSE 1.10
    END
FROM RAW_ASSET_REGISTER r;

-- ---------------------------------------------------------------------
-- Domain A — metering and utility billing
-- Two feeds that disagree: smart meters (granular, gappy, only on some
-- assets) and monthly invoices (complete, sometimes estimated).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW_UTILITY_INVOICES (
    invoice_id      VARCHAR(40)  PRIMARY KEY,
    source_asset_ref VARCHAR(30) NOT NULL,
    billing_month   DATE         NOT NULL,
    energy_carrier  VARCHAR(30)  NOT NULL, -- Electricity, Natural gas, District heat, Heating oil
    consumption_kwh NUMBER(14,2) NOT NULL,
    cost_eur        NUMBER(12,2) NOT NULL,
    is_estimated    BOOLEAN      NOT NULL,
    supplier_name   VARCHAR(60)  NOT NULL
)
COMMENT = 'Monthly utility invoices as received. Some months are supplier estimates.';

CREATE OR REPLACE TABLE RAW_METER_READINGS (
    reading_id       VARCHAR(40)  PRIMARY KEY,
    source_asset_ref VARCHAR(30)  NOT NULL,
    reading_month    DATE         NOT NULL,
    meter_serial     VARCHAR(30)  NOT NULL,
    readings_expected NUMBER(6,0) NOT NULL,
    readings_received NUMBER(6,0) NOT NULL,
    consumption_kwh  NUMBER(14,2) NOT NULL,
    reading_quality  VARCHAR(20)  NOT NULL  -- Complete, Partial, Sparse
)
COMMENT = 'Smart meter monthly aggregates. Only ~60% of assets are metered, and coverage is uneven.';

-- Monthly energy per asset per carrier, 2023-01 to 2026-06.
-- Physics-ish: sector base intensity x EPC efficiency x heating system,
-- split across carriers, with a winter heating peak.
INSERT INTO RAW_UTILITY_INVOICES
(invoice_id, source_asset_ref, billing_month, energy_carrier,
 consumption_kwh, cost_eur, is_estimated, supplier_name)
WITH months AS (
    SELECT DATEADD(month, SEQ4(), DATE '2023-01-01') AS billing_month,
           SEQ4() AS m_idx
    FROM TABLE(GENERATOR(ROWCOUNT => 42))
),
asset_profile AS (
    SELECT
        a.asset_id,
        TRY_TO_NUMBER(RIGHT(a.asset_id, 5)) AS asset_num,
        a.floor_area_m2,
        a.efficiency_factor,
        a.heating_system,
        -- Annual kWh/m2 before heating-system adjustment
        CASE a.asset_sector
            WHEN 'Office'       THEN 180
            WHEN 'Retail'       THEN 220
            WHEN 'Logistics'    THEN  90
            WHEN 'Nursing home' THEN 310
            WHEN 'Residential'  THEN 150
            ELSE 260  -- Hotel
        END AS base_intensity,
        -- Heat pumps move much less energy for the same service
        CASE a.heating_system
            WHEN 'Heat pump'           THEN 0.55
            WHEN 'Electric resistance' THEN 1.15
            ELSE 1.00
        END AS system_factor
    FROM DIM_ASSET a
),
carriers AS (
    -- Carrier shares per heating system. Solar and heat-pump self-supply
    -- simply do not appear as an invoiced carrier.
    SELECT 'Gas boiler'          AS heating_system, 'Natural gas'   AS energy_carrier, 0.75 AS carrier_share UNION ALL
    SELECT 'Gas boiler',          'Electricity',    0.25 UNION ALL
    SELECT 'Gas boiler + solar',  'Natural gas',    0.60 UNION ALL
    SELECT 'Gas boiler + solar',  'Electricity',    0.30 UNION ALL
    SELECT 'Electric resistance', 'Electricity',    1.00 UNION ALL
    SELECT 'Heat pump',           'Electricity',    1.00 UNION ALL
    SELECT 'District heating',    'District heat',  0.70 UNION ALL
    SELECT 'District heating',    'Electricity',    0.30 UNION ALL
    SELECT 'Oil boiler',          'Heating oil',    0.75 UNION ALL
    SELECT 'Oil boiler',          'Electricity',    0.25
)
SELECT
    'INV-' || p.asset_id || '-' || TO_VARCHAR(m.billing_month, 'YYYYMM') || '-' ||
        LEFT(c.energy_carrier, 3)                                  AS invoice_id,
    p.asset_id                                                     AS source_asset_ref,
    m.billing_month,
    c.energy_carrier,
    ROUND(
        p.floor_area_m2 * p.base_intensity * p.efficiency_factor * p.system_factor
        * c.carrier_share / 12.0
        -- Winter peak: heating carriers swing far more than electricity.
        * (1 + CASE WHEN c.energy_carrier = 'Electricity' THEN 0.12 ELSE 0.45 END
                 * COS(2 * PI() * (MONTH(m.billing_month) - 1) / 12.0))
        -- Slow efficiency drift downwards over the period.
        * (1 - 0.004 * m.m_idx)
    , 2)                                                           AS consumption_kwh,
    ROUND(
        p.floor_area_m2 * p.base_intensity * p.efficiency_factor * p.system_factor
        * c.carrier_share / 12.0
        * CASE c.energy_carrier
              WHEN 'Electricity'   THEN 0.21
              WHEN 'Natural gas'   THEN 0.09
              WHEN 'District heat' THEN 0.11
              ELSE 0.13
          END
    , 2)                                                           AS cost_eur,
    -- One month in nine arrives as a supplier estimate.
    (MOD(m.m_idx * 3 + p.asset_num, 9) = 0)                        AS is_estimated,
    CASE MOD(p.asset_num + m.m_idx, 5)
        WHEN 0 THEN 'EDF Entreprises' WHEN 1 THEN 'Engie Business'
        WHEN 2 THEN 'E.ON Energie'    WHEN 3 THEN 'Vattenfall'
        ELSE 'Iberdrola Empresas'
    END                                                            AS supplier_name
FROM asset_profile p
JOIN carriers c ON c.heating_system = p.heating_system
CROSS JOIN months m;

-- Smart meters cover roughly 60% of assets, with uneven completeness.
-- This is the "noisy and sparse" problem Deepki described, made explicit
-- rather than hidden.
INSERT INTO RAW_METER_READINGS
(reading_id, source_asset_ref, reading_month, meter_serial,
 readings_expected, readings_received, consumption_kwh, reading_quality)
WITH metered AS (
    SELECT a.asset_id,
           TRY_TO_NUMBER(RIGHT(a.asset_id, 5)) AS asset_num
    FROM   DIM_ASSET a
    WHERE  MOD(TRY_TO_NUMBER(RIGHT(a.asset_id, 5)), 5) < 3   -- 60% metered
),
elec AS (
    SELECT source_asset_ref, billing_month, SUM(consumption_kwh) AS kwh
    FROM   RAW_UTILITY_INVOICES
    WHERE  energy_carrier = 'Electricity'
    GROUP  BY 1, 2
)
SELECT
    'MTR-' || m.asset_id || '-' || TO_VARCHAR(e.billing_month, 'YYYYMM'),
    m.asset_id,
    e.billing_month,
    'SM' || LPAD((m.asset_num * 7919 % 100000)::VARCHAR, 8, '0'),
    DAY(LAST_DAY(e.billing_month)) * 48                       AS readings_expected,
    -- Completeness varies by asset and drifts with the month.
    ROUND(DAY(LAST_DAY(e.billing_month)) * 48 * cov.coverage) AS readings_received,
    -- Metered kWh is the invoiced electricity scaled by actual coverage,
    -- which is why the two feeds disagree and need reconciling.
    ROUND(e.kwh * cov.coverage, 2)                            AS consumption_kwh,
    CASE WHEN cov.coverage >= 0.98 THEN 'Complete'
         WHEN cov.coverage >= 0.80 THEN 'Partial'
         ELSE 'Sparse'
    END                                                       AS reading_quality
FROM metered m
JOIN elec e ON e.source_asset_ref = m.asset_id
JOIN (
    SELECT asset_id,
           CASE
               WHEN MOD(asset_num, 17) = 0 THEN 0.62   -- chronically bad meters
               WHEN MOD(asset_num, 11) = 0 THEN 0.85
               ELSE 1.00
           END AS coverage
    FROM metered
) cov ON cov.asset_id = m.asset_id;

-- ---------------------------------------------------------------------
-- Harmonised monthly energy and carbon fact (silver)
-- Reconciles the two feeds: invoices are authoritative for volume, meters
-- supply the data-quality signal. Carbon is computed with the country grid
-- factor for electricity, so the same kWh emits very differently in France
-- and Poland.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_ENERGY_MONTHLY (
    energy_fact_id        VARCHAR(50)  PRIMARY KEY,
    asset_id              VARCHAR(30)  NOT NULL,
    reading_month         DATE         NOT NULL,
    reading_year          NUMBER(4,0)  NOT NULL,
    energy_kwh            NUMBER(14,2) NOT NULL,
    energy_cost_eur       NUMBER(12,2) NOT NULL,
    co2e_kg               NUMBER(14,2) NOT NULL,
    fossil_share_pct      NUMBER(5,2)  NOT NULL,
    is_estimated          BOOLEAN      NOT NULL,
    is_metered            BOOLEAN      NOT NULL,
    data_completeness_pct NUMBER(5,2)  NOT NULL
)
COMMENT = 'Monthly energy and carbon per asset, harmonised from invoices and meters, with a data-quality signal.';

INSERT INTO FACT_ENERGY_MONTHLY
WITH factors AS (
    SELECT DISTINCT pathway_country, grid_carbon_factor
    FROM   DIM_CRREM_PATHWAY
),
billed AS (
    SELECT
        i.source_asset_ref                       AS asset_id,
        i.billing_month                          AS reading_month,
        SUM(i.consumption_kwh)                   AS energy_kwh,
        SUM(i.cost_eur)                          AS energy_cost_eur,
        -- Carbon by carrier. Electricity uses the country grid factor;
        -- fossil carriers use standard combustion factors.
        SUM(i.consumption_kwh *
            CASE i.energy_carrier
                WHEN 'Electricity'   THEN f.grid_carbon_factor
                WHEN 'Natural gas'   THEN 0.2020
                WHEN 'District heat' THEN 0.1500
                ELSE 0.2670  -- Heating oil
            END)                                 AS co2e_kg,
        SUM(CASE WHEN i.energy_carrier IN ('Natural gas','Heating oil')
                 THEN i.consumption_kwh ELSE 0 END) AS fossil_kwh,
        MAX(CASE WHEN i.is_estimated THEN 1 ELSE 0 END) AS any_estimated
    FROM   RAW_UTILITY_INVOICES i
    JOIN   DIM_ASSET a ON a.asset_id = i.source_asset_ref
    JOIN   factors f   ON f.pathway_country = a.asset_country
    GROUP  BY 1, 2
)
SELECT
    'EF-' || b.asset_id || '-' || TO_VARCHAR(b.reading_month, 'YYYYMM'),
    b.asset_id,
    b.reading_month,
    YEAR(b.reading_month),
    ROUND(b.energy_kwh, 2),
    ROUND(b.energy_cost_eur, 2),
    ROUND(b.co2e_kg, 2),
    ROUND(100 * b.fossil_kwh / NULLIF(b.energy_kwh, 0), 2),
    (b.any_estimated = 1),
    (m.source_asset_ref IS NOT NULL),
    COALESCE(ROUND(100.0 * m.readings_received / NULLIF(m.readings_expected, 0), 2), 0)
FROM billed b
LEFT JOIN RAW_METER_READINGS m
       ON m.source_asset_ref = b.asset_id
      AND m.reading_month    = b.reading_month;

-- ---------------------------------------------------------------------
-- Retrofit action catalogue
-- Mirrors the curated action catalogue behind Deepki's Investment Plan.
-- Act 3 recommendations are grounded here rather than invented by the model.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_RETROFIT_ACTION (
    action_id            VARCHAR(12)  PRIMARY KEY,
    action_name          VARCHAR(120) NOT NULL,
    action_category      VARCHAR(40)  NOT NULL,
    applies_to_sector    VARCHAR(60)  NOT NULL,
    applies_to_heating   VARCHAR(60)  NOT NULL,
    capex_eur_per_m2     NUMBER(8,2)  NOT NULL,
    energy_saving_pct    NUMBER(5,2)  NOT NULL,
    carbon_saving_pct    NUMBER(5,2)  NOT NULL,
    payback_years        NUMBER(5,1)  NOT NULL,
    disruption_level     VARCHAR(20)  NOT NULL,
    action_description   VARCHAR(600) NOT NULL
)
COMMENT = 'Curated retrofit actions with capex, savings and payback. Grounds the Act 3 recommendation.';

INSERT INTO DIM_RETROFIT_ACTION VALUES
('RA001','Replace gas boiler with air-source heat pump','Heating','Any','Gas boiler',185.00,42.00,68.00,9.5,'High','Full replacement of the gas boiler plant with an air-source heat pump, including emitter upgrades where flow temperatures require it. The largest single carbon lever for a gas-heated asset because it moves the load onto the electricity grid, which decarbonises over time. Highest capex and highest disruption, so it is usually scheduled at plant end-of-life.'),
('RA002','Replace electric resistance heating with heat pump','Heating','Any','Electric resistance',148.00,52.00,52.00,6.5,'High','Swap direct electric resistance heating for a heat pump. Cuts delivered energy by roughly half for the same heat output because the coefficient of performance does the work. Payback is faster than the gas-to-heat-pump case since electricity is the more expensive carrier.'),
('RA003','Hydraulic balancing and flow temperature reset','Heating','Any','Gas boiler',6.50,9.00,9.00,1.2,'Low','Rebalance the hydraulic circuit and lower the heating flow temperature to the minimum that still satisfies the space. Almost no capex, no tenant disruption, and it is a prerequisite for any later heat pump because it proves the emitters work at lower temperatures.'),
('RA004','Building management system optimisation','Controls','Office,Retail,Hotel','Any',12.00,14.00,14.00,1.8,'Low','Retune BMS schedules, setpoints and dead bands against actual occupancy rather than design assumptions. Frequently recovers double-digit savings on assets where schedules were never revisited after fit-out.'),
('RA005','Install submetering by end use','Metering','Any','Any',8.00,4.00,4.00,3.5,'Low','Add submeters on heating, cooling, lighting and plug loads. The direct saving is modest, but it converts an opaque asset into a measurable one and is what makes every later action verifiable.'),
('RA006','LED relighting with presence detection','Lighting','Any','Any',22.00,11.00,11.00,2.4,'Medium','Replace remaining fluorescent and halogen fittings with LED, adding presence and daylight detection. Well-understood, low-risk, and the savings persist without behavioural change.'),
('RA007','Roof insulation upgrade','Envelope','Any','Any',48.00,13.00,13.00,7.8,'Medium','Add or upgrade roof insulation to current standards. Best combined with planned roof works, since access dominates the cost. Reduces peak heating demand, which in turn allows smaller heat pump plant later.'),
('RA008','Window replacement to triple glazing','Envelope','Office,Residential,Nursing home','Any',165.00,16.00,16.00,14.0,'High','Replace single or early double glazing with triple glazing. Long payback on energy alone, so it is normally justified by occupant comfort, acoustics and asset value rather than by the energy line.'),
('RA009','Rooftop solar PV installation','Generation','Logistics,Retail,Office','Any',95.00,18.00,22.00,6.2,'Medium','Install rooftop PV sized to the on-site load. Logistics and retail sheds have the roof area and the daytime load profile that make this the strongest fit.'),
('RA010','Heat recovery on ventilation','Ventilation','Office,Nursing home,Hotel','Any',38.00,12.00,12.00,5.4,'Medium','Fit heat recovery to the main air handling units. Particularly effective in nursing homes and hotels where high ventilation rates are required continuously for health reasons.'),
('RA011','Domestic hot water heat pump','Hot water','Nursing home,Hotel,Residential','Any',52.00,15.00,24.00,5.8,'Medium','Dedicated heat pump for domestic hot water. In nursing homes and hotels, hot water is a year-round base load, so this decouples a large fossil demand from the heating season.'),
('RA012','Switch electricity supply to certified renewable tariff','Procurement','Any','Any',0.50,0.00,34.00,0.3,'Low','Move the electricity supply to a certified renewable tariff. No energy saving at all, and it only affects market-based reporting, not the location-based figure. Cheap and fast, but it should never be presented as a substitute for physical measures.'),
('RA013','Oil boiler to district heating connection','Heating','Any','Oil boiler',110.00,8.00,44.00,8.9,'High','Abandon on-site oil combustion and connect to the district heating network where one is available. The carbon saving comes almost entirely from the carrier switch rather than from reduced demand.'),
('RA014','Pipework and valve insulation','Heating','Any','Any',3.50,5.00,5.00,0.9,'Low','Insulate exposed distribution pipework, valves and flanges in plant rooms and risers. The cheapest measure in the catalogue and it pays back inside a year, yet it is routinely left undone.'),
('RA015','Variable speed drives on pumps and fans','Controls','Any','Any',14.00,8.00,8.00,2.9,'Medium','Fit variable speed drives so distribution equipment modulates with demand instead of running at fixed speed. Applies to almost every asset with central plant.'),
('RA016','Cold aisle containment and cooling setpoint review','Cooling','Office,Logistics','Any',18.00,7.00,7.00,3.1,'Medium','Contain cooling in server and equipment rooms and revisit setpoints, which are usually far lower than equipment actually requires.'),
('RA017','Occupancy-based ventilation control','Ventilation','Office,Retail','Any',16.00,9.00,9.00,3.3,'Low','Drive ventilation from CO2 and occupancy sensing rather than fixed schedules. Reduces conditioning of unoccupied space, which is significant in assets with hybrid working patterns.'),
('RA018','Wall insulation, external render system','Envelope','Residential,Nursing home','Any',142.00,19.00,19.00,13.5,'High','External wall insulation with a new render finish. Transformative for envelope performance and occupant comfort, but it is a major works programme with planning and facade implications.'),
('RA019','Smart thermostatic radiator valves','Controls','Residential,Nursing home,Hotel','Any',9.50,10.00,10.00,2.1,'Low','Room-level smart TRVs giving per-space scheduling. Especially effective where rooms are intermittently occupied, which is the norm in hotels and much of residential.'),
('RA020','Compressed air leak survey and repair','Process','Logistics','Any',4.00,6.00,6.00,1.1,'Low','Survey and repair compressed air leaks. Cheap, quick, and typically recovers a surprising share of a logistics asset load.'),
('RA021','Energy management staff training and monitoring routine','Operations','Any','Any',2.00,5.00,5.00,0.7,'Low','Establish a monthly monitoring and targeting routine with trained site staff. No technology at all, and the savings depend entirely on the routine surviving beyond the first quarter, which is why it pairs with submetering.'),
('RA022','Replace end-of-life chiller with high-efficiency unit','Cooling','Office,Retail,Hotel','Any',72.00,10.00,10.00,8.2,'High','Replace an ageing chiller with a high-efficiency low-GWP refrigerant unit. Best timed with plant end-of-life; the refrigerant change also removes a future compliance exposure.'),
('RA023','Destratification fans in high-bay space','Heating','Logistics','Any',7.00,9.00,9.00,1.6,'Low','Fit destratification fans to push warm air back down in high-bay space. Cheap and effective wherever ceiling heights create a large vertical temperature gradient.'),
('RA024','Battery storage with load shifting','Generation','Logistics,Retail','Any',88.00,3.00,6.00,9.8,'Medium','Battery storage to shift load away from peak periods. Justified mainly by tariff arbitrage and resilience rather than by carbon, and it pairs naturally with rooftop PV.');

-- ---------------------------------------------------------------------
-- Audit report extracts, for the agent's search tool
-- Short unstructured notes of the kind Deepki holds but barely exploits.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ASSET_AUDIT_NOTE (
    note_id      VARCHAR(20)  PRIMARY KEY,
    asset_id     VARCHAR(30)  NOT NULL,
    note_date    DATE         NOT NULL,
    auditor_firm VARCHAR(60)  NOT NULL,
    note_title   VARCHAR(140) NOT NULL,
    note_text    VARCHAR(2000) NOT NULL
)
COMMENT = 'On-site audit extracts. Unstructured context the agent can cite alongside the numbers.';

INSERT INTO ASSET_AUDIT_NOTE VALUES
('AN001','AST-00500','2025-11-18','Drees & Sommer','Site audit, Wohnstift Frankfurt 36 — heating and DHW','Direct electric resistance heating throughout, installed during the 1998 refurbishment and never replaced. Panel heaters are individually switched with no central control, so setback is impossible outside of manual intervention by night staff. Domestic hot water is produced by immersion cylinders held at 65C continuously for legionella control, which represents a large year-round electrical base load independent of the heating season. The building has adequate plant space and a suitable external courtyard for an air-source heat pump array. Emitter survey confirms oversized panel areas, meaning a low flow temperature system would satisfy the space without emitter replacement. Residents are present continuously, so any works programme must be phased wing by wing.'),
('AN002','AST-00350','2025-09-30','Drees & Sommer','Site audit, Wohnstift Frankfurt 51 — envelope and controls','Uninsulated cavity walls and original single-glazed windows on the north elevation. Electric resistance heating with no zoning; the whole floor plate is served by one thermostat located in a south-facing corridor, which causes chronic overheating in resident rooms and complaints logged with the operator. Hot water distribution pipework in the basement plant room is entirely uninsulated over an estimated 140 metres. Metering is limited to a single incoming supply, so no end-use breakdown is possible without submetering. The asset is a strong candidate for the standard sequence: insulate pipework, add zone controls and submetering, then replace the heating system.'),
('AN003','AST-00470','2025-10-22','Arcadis Germany','Site audit, Wohnstift Hamburg 45 — plant condition','Electric resistance heating at end of serviceable life; the operator reports repeated element failures over the last two winters. District heating is available at the boundary, with a connection point approximately 60 metres from the plant room, which makes a carrier switch materially cheaper here than at the other assets in this portfolio. Ventilation is natural throughout with no heat recovery. Roof was replaced in 2021 but insulation was not upgraded at the time, which was a missed opportunity now costly to revisit.'),
('AN004','AST-00290','2025-12-03','Arcadis Germany','Site audit, Wohnstift Frankfurt 12 — metering and data quality','The half-hourly meter has been reporting intermittently since a communications module fault in March. Roughly a third of expected readings are missing, so consumption for this asset is reconstructed from monthly invoices rather than measured. This should be resolved before any retrofit, otherwise there is no reliable baseline against which to verify savings. Heating is electric resistance with individual room controls added in 2019, which is why intensity is slightly better than its sister assets despite the same system type.'),
('AN005','AST-00380','2025-08-14','TUV Sud','Site audit, Stadthaus Cologne 55 — worst-performing asset','The poorest performer in the portfolio on a per-square-metre basis. Electric resistance heating, EPC G, no insulation to walls or roof, and single glazing throughout. The operator maintains elevated internal temperatures of 24C year round on clinical advice for the resident profile, which is legitimate and should not be treated as waste, but it does mean demand reduction has to come from the envelope and the heat source rather than from setpoints. Given the condition of every element, a deep retrofit at next void period is more economic than a sequence of partial measures.'),
('AN006','AST-00120','2025-07-09','Deepki Energy Services','Portfolio review note — gas-heated care assets','Across the gas-heated care assets in this portfolio the pattern is consistent: boilers installed between 2004 and 2011, oversized for current demand, running at fixed high flow temperatures with no weather compensation. Hydraulic balancing has never been carried out on any of the assets inspected. This is the cheapest available intervention and it is also a prerequisite for later heat pump conversion, because it establishes whether the emitters can deliver at lower flow temperatures. Recommend it as the first move across the whole cluster rather than asset by asset.');
