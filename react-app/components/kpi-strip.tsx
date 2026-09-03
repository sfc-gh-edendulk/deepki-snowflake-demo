"use client"

/**
 * KPI strip — the four numbers an energy manager checks before asking anything.
 *
 * Reads /api/portfolio (a direct table read), not the agent, so the panel has
 * something on screen while the agent is still thinking.
 */

import { useQuery } from "@tanstack/react-query"
import { Card, CardContent } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { count, toNumber } from "@/lib/format"

interface PortfolioPayload {
  summary: Record<string, unknown> | null
  year: number
  error?: string
}

const M2 = new Intl.NumberFormat("en-GB", { maximumFractionDigits: 0 })
const M2_COMPACT = new Intl.NumberFormat("en-GB", {
  maximumFractionDigits: 2,
  minimumFractionDigits: 2,
})

/**
 * Square metres. Portfolio areas run into eight figures, so anything at a
 * million or above is compacted; below that the grouped integer is readable.
 */
function area(value: unknown): string {
  const n = toNumber(value)
  if (n === null) return "—"
  if (Math.abs(n) >= 1_000_000) return `${M2_COMPACT.format(n / 1_000_000)}M m²`
  return `${M2.format(n)} m²`
}

function Tile({
  label,
  value,
  hint,
  loading,
  emphasis = false,
}: {
  label: string
  value: string
  hint: string
  loading: boolean
  /** Marks the genuinely negative metric. Exactly one tile should set this. */
  emphasis?: boolean
}) {
  return (
    <Card className="relative overflow-hidden">
      {/* Accent edge: teal by default, attention orange for the bad number. */}
      <span
        aria-hidden
        className={`absolute inset-y-0 left-0 w-1 ${
          emphasis ? "bg-brand-orange" : "bg-brand-teal"
        }`}
      />
      <CardContent className="p-5 pl-6">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {label}
        </p>
        {loading ? (
          <Skeleton className="mt-2 h-8 w-28" />
        ) : (
          <p
            className={`mt-2 text-2xl font-semibold tabular-nums ${
              emphasis
                ? "text-brand-orange"
                : "text-brand-teal-darkest dark:text-brand-teal-bright"
            }`}
          >
            {value}
          </p>
        )}
        {loading ? (
          <Skeleton className="mt-2 h-3 w-40" />
        ) : (
          <p className="mt-1.5 text-xs leading-snug text-muted-foreground">{hint}</p>
        )}
      </CardContent>
    </Card>
  )
}

export function KpiStrip() {
  const { data, isLoading, error } = useQuery<PortfolioPayload>({
    queryKey: ["portfolio"],
    queryFn: async () => {
      const res = await fetch("/api/portfolio")
      const json = (await res.json()) as PortfolioPayload
      if (!res.ok) throw new Error(json.error ?? "Failed to load portfolio summary")
      return json
    },
  })

  const s = data?.summary ?? null
  const year = data?.year ?? 2025
  const strandedPct = toNumber(s?.STRANDED_PCT)

  return (
    <section aria-label="Portfolio summary">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Tile
          label="Monitored area"
          value={area(s?.MONITORED_M2)}
          hint={`${count(s?.TOTAL_ASSETS)} assets reporting in ${year}`}
          loading={isLoading}
        />
        <Tile
          label="Stranded area"
          value={area(s?.STRANDED_M2)}
          hint="Floor area above its CRREM threshold"
          loading={isLoading}
        />
        <Tile
          label="Stranded share"
          value={strandedPct === null ? "—" : `${strandedPct.toFixed(1)}%`}
          hint="Above CRREM threshold, share of monitored area"
          loading={isLoading}
          emphasis
        />
        <Tile
          label="Off-pathway assets"
          value={count(s?.STRANDED_ASSETS)}
          hint="Assets missing their decarbonisation pathway"
          loading={isLoading}
        />
      </div>

      {error && (
        <p className="mt-3 text-sm text-destructive">
          Could not load portfolio figures: {error instanceof Error ? error.message : String(error)}
        </p>
      )}
    </section>
  )
}
