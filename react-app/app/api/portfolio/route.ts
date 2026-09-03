/**
 * Portfolio headline figures for the KPI strip.
 *
 * GET /api/portfolio
 *
 * Read straight from ASSET_YEAR_PERFORMANCE rather than through the agent: these
 * four numbers must be on screen instantly, while the agent takes 30-90 seconds.
 *
 * `querySnowflake` does not support bound parameters, so the reporting year is
 * inlined. It comes from a module constant, never from the request.
 */

import { querySnowflake } from "@/lib/snowflake"
import { REPORTING_YEAR, TABLES } from "@/lib/constants"

export const dynamic = "force-dynamic"

export interface PortfolioSummary {
  TOTAL_ASSETS: unknown
  MONITORED_M2: unknown
  STRANDED_M2: unknown
  STRANDED_PCT: unknown
  STRANDED_ASSETS: unknown
}

export async function GET() {
  try {
    const rows = await querySnowflake(`
      SELECT COUNT(*) AS TOTAL_ASSETS, ROUND(SUM(floor_area_m2)) AS MONITORED_M2,
             ROUND(SUM(stranded_floor_area_m2)) AS STRANDED_M2,
             ROUND(100.0*SUM(stranded_floor_area_m2)/SUM(floor_area_m2),1) AS STRANDED_PCT,
             SUM(CASE WHEN is_off_pathway THEN 1 ELSE 0 END) AS STRANDED_ASSETS
      FROM ${TABLES.assetYearPerformance} WHERE reading_year = ${REPORTING_YEAR}
    `)

    return Response.json({ summary: rows[0] ?? null, year: REPORTING_YEAR })
  } catch (e) {
    console.error("Portfolio route error:", e)
    return Response.json(
      {
        error:
          e instanceof Error
            ? e.message
            : `Failed to load portfolio summary for ${REPORTING_YEAR}.`,
      },
      { status: 500 },
    )
  }
}
