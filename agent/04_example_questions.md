# Example questions

Every question here has been run against the deployed agent. Figures are from the loaded
synthetic data for reporting year 2025.

## Act 1 — WHAT

> Across all the portfolios we monitor, how much floor area is already off its CRREM
> decarbonisation pathway in 2025, and how much annual subscription revenue sits with the
> most exposed clients?

Expected shape of the answer: about **5.5 million m² of 11.0 million m², so 50.1% of monitored
floor area**, is above its pathway threshold. 592 of 1,200 assets. The clients carrying more
than 300,000 m² of stranded area between them represent **€1.475M of €2.468M total ACV**.

Why it matters in the room: this single answer crosses metering data, the client's asset
register, external CRREM thresholds and Deepki's own subscription data. No one system holds
all four.

## Act 2 — WHY

> Which client drives the largest share of that stranded floor area, and what is the pattern
> by sector and heating system?

Expected: **Rhenus Immobilien GmbH, about 2.03M m², roughly 37% of all stranded area** — more
than three times the next client. Within Rhenus, the concentration is sharper still:

- Gas-boiler nursing homes: about half of their stranded area
- Electric-resistance nursing homes: about a quarter, and the worst intensity gap of any
  cluster in the book, roughly 100 kgCO2e/m² above threshold

The German grid carbon factor (0.366 kgCO2e/kWh against 0.058 in France) is doing much of the
work here, which is exactly the point Deepki makes in its own published index.

## Act 3 — HOW + ACTION

> What retrofit actions do you recommend for Rhenus Immobilien's five worst assets, what is
> the payback, and who at the client should I contact?

Expected: the agent should name the assets (the `Wohnstift` and `Stadthaus` electric-resistance
care homes), pull actions from the catalogue rather than inventing them, and name
**Andrea Vogt, andrea.vogt@rhenus-immo.de** as the energy manager.

The recommendation should sequence properly:
1. `RA014` pipework insulation and `RA003` hydraulic balancing — under 1.5 year payback, no
   disruption, and the balancing is a prerequisite for anything later
2. `RA002` electric resistance to heat pump — 6.5 year payback, 52% energy saving, the main
   lever for this cluster
3. `RA011` domestic hot water heat pump — the audit notes flag continuous 65°C cylinders as a
   year-round base load

Then the presenter fires the Gmail draft. See `DEMO_SCRIPT.md`.

## Supporting questions, if the room pulls in a direction

Sector-aware metrics (proves the semantic layer handles heterogeneous client models):
> For our nursing home assets, show energy intensity per occupied room rather than per square
> metre, and compare that against the office portfolio.

Data quality honesty (Romain and Thibaut will probe this):
> How much of the 2025 consumption is based on estimated invoices or incomplete meter data,
> and which assets have the worst coverage?

Grid factor versus consumption (the Deepki Index argument):
> Compare our French and German office assets on energy intensity and on carbon intensity.
> Where does the difference come from?

Unstructured retrieval (exercises the search tool):
> What did the site audits say about the heating systems in the worst Rhenus assets?

Isolation (the CTO's compliance question):
> Show me total stranded area by client.

Run the last one under a tenant role and the agent returns only that tenant's row. Same agent,
same question, scoped answer. See `05_row_access_policy.sql`.

## Smoke query behind the WHAT figure

```sql
WITH asset_year AS (
  SELECT f.asset_id, a.client_id, a.floor_area_m2,
         SUM(f.co2e_kg) / a.floor_area_m2  AS co2_intensity,
         MAX(p.threshold_kgco2e_per_m2)    AS threshold
  FROM   CUSTOM_DEMOS.DEEPKI.FACT_ENERGY_MONTHLY f
  JOIN   CUSTOM_DEMOS.DEEPKI.DIM_ASSET a ON a.asset_id = f.asset_id
  JOIN   CUSTOM_DEMOS.DEEPKI.DIM_CRREM_PATHWAY p
         ON  p.pathway_country = a.asset_country
         AND p.pathway_sector  = a.asset_sector
         AND p.pathway_year    = f.reading_year
  WHERE  f.reading_year = 2025
  GROUP  BY f.asset_id, a.client_id, a.floor_area_m2
)
SELECT c.client_name,
       COUNT(*)                                                      AS stranded_assets,
       ROUND(SUM(ay.floor_area_m2))                                  AS stranded_m2,
       ROUND(100 * RATIO_TO_REPORT(SUM(ay.floor_area_m2)) OVER (), 1) AS pct_of_stranded,
       MAX(c.subscription_acv_eur)                                   AS acv_eur,
       MAX(c.energy_manager_email)                                   AS contact
FROM   asset_year ay
JOIN   CUSTOM_DEMOS.DEEPKI.DIM_CLIENT c ON c.client_id = ay.client_id
WHERE  ay.co2_intensity > ay.threshold
GROUP  BY c.client_name
ORDER  BY stranded_m2 DESC;
```

Gate: 10-50 rows, top client at or above 30% of stranded area, contact populated. Currently
15 rows, top client 36.8%.
