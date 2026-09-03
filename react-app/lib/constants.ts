/** App title — displayed in the nav header and browser tab */
export const APP_TITLE = "Deepki Portfolio Copilot"

/** Path to the logo in /public (used in the header and as favicon) */
export const LOGO_SRC = "/icon.svg"

/** Fully qualified Cortex Agent this app talks to. */
export const AGENT = {
  database: "CUSTOM_DEMOS",
  schema: "DEEPKI",
  name: "DEEPKI_PORTFOLIO_AGENT",
} as const

/** Fully qualified tables read directly (outside the agent) for the KPI strip. */
export const TABLES = {
  assetYearPerformance: "CUSTOM_DEMOS.DEEPKI.ASSET_YEAR_PERFORMANCE",
} as const

/** Reporting year the KPI strip summarises. */
export const REPORTING_YEAR = 2025
