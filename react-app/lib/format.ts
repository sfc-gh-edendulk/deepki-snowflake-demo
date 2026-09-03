"use client"

/**
 * Shared formatting helpers.
 *
 * Every value rendered by this app comes from a dbt model, so these are purely
 * presentational: they format, they never derive.
 */

/** Compact currency. Null, undefined, and NaN all render as an em dash. */
export function money(value: unknown): string {
  const n = toNumber(value)
  if (n === null) return "—"
  const abs = Math.abs(n)
  if (abs >= 1_000_000_000) return `$${(n / 1_000_000_000).toFixed(1)}B`
  if (abs >= 1_000_000) return `$${(n / 1_000_000).toFixed(1)}M`
  if (abs >= 1_000) return `$${(n / 1_000).toFixed(1)}K`
  return `$${n.toFixed(0)}`
}

/** Format a 0-1 fraction as a percentage. */
export function percent(value: unknown, digits = 1): string {
  const n = toNumber(value)
  if (n === null) return "—"
  return `${(n * 100).toFixed(digits)}%`
}

/** Thousands-separated integer. */
export function count(value: unknown): string {
  const n = toNumber(value)
  if (n === null) return "—"
  return n.toLocaleString("en-US", { maximumFractionDigits: 0 })
}

/** Signed percentage, for deltas. */
export function signedPercent(value: unknown, digits = 1): string {
  const n = toNumber(value)
  if (n === null) return "—"
  const sign = n > 0 ? "+" : ""
  return `${sign}${(n * 100).toFixed(digits)}%`
}

/**
 * Coerce a Snowflake value to a number.
 *
 * The Node driver returns NUMBER columns as strings when precision could exceed
 * a JS float, so a plain `as number` cast is not safe here.
 */
export function toNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null
  if (typeof value === "number") return Number.isFinite(value) ? value : null
  if (typeof value === "string") {
    const trimmed = value.trim()
    if (trimmed === "") return null
    const n = Number(trimmed)
    return Number.isFinite(n) ? n : null
  }
  return null
}

/** Short month label, e.g. "Mar 26". Expects an ISO date string. */
export function monthLabel(iso: string): string {
  const d = new Date(`${iso}T00:00:00Z`)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleDateString("en-US", {
    month: "short",
    year: "2-digit",
    timeZone: "UTC",
  })
}

/** Human-readable engagement band labels. */
export const ENGAGEMENT_LABELS: Record<string, string> = {
  active: "Active",
  cooling: "Cooling",
  at_risk: "At risk",
  dormant: "Dormant",
  churned: "Churned",
  never_ordered: "Never ordered",
}

/** Severity order, so charts read as a funnel from healthy to lost. */
export const ENGAGEMENT_ORDER = [
  "active",
  "cooling",
  "at_risk",
  "dormant",
  "churned",
  "never_ordered",
]

/** Brand-consistent chart palette. */
export const CHART_COLORS = [
  "#0284C7",
  "#7DD3FC",
  "#075985",
  "#38BDF8",
  "#0C4A6E",
  "#BAE6FD",
  "#0369A1",
]
