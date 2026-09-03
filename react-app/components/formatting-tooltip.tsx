"use client"

/**
 * Chart tooltip that formats values.
 *
 * The shared ChartTooltip in components/chart-utils.tsx renders raw numbers via
 * toLocaleString and accepts no formatter, which would show revenue as
 * "20876458" instead of "$20.9M". This variant keeps the same CSS-variable
 * styling (so it stays readable in dark mode) but takes a per-series formatter.
 */

interface TooltipEntry {
  name: string
  value: number | string | null
  color: string
  dataKey: string
}

interface FormattingTooltipProps {
  active?: boolean
  payload?: TooltipEntry[]
  label?: string
  /** Formats a value given its series name. */
  format: (value: unknown, seriesName: string) => string
}

export function FormattingTooltip({
  active,
  payload,
  label,
  format,
}: FormattingTooltipProps) {
  if (!active || !payload?.length) return null

  return (
    <div
      style={{
        background: "var(--popover)",
        color: "var(--popover-foreground)",
        border: "1px solid var(--border)",
        borderRadius: 6,
        padding: "8px 12px",
        fontSize: 12,
        boxShadow: "0 4px 12px rgba(0,0,0,0.35)",
        minWidth: 140,
      }}
    >
      {label && (
        <p style={{ marginBottom: 4, fontWeight: 600, marginTop: 0 }}>{label}</p>
      )}
      {payload.map((entry) => (
        <p key={entry.dataKey} style={{ color: entry.color, margin: 0 }}>
          {entry.name}: {format(entry.value, entry.name)}
        </p>
      ))}
    </div>
  )
}
