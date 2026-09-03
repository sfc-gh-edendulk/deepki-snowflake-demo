"use client"

/**
 * AppShell — the product chrome around the copilot.
 *
 * The point of this component is framing: a left rail and a section top bar so
 * the copilot reads as one screen inside a larger platform, not a standalone
 * tool. Only the Copilot entry is live; the rest of the rail is deliberately
 * inert and says so, because a dead link found in front of an audience is
 * worse than one that is obviously not part of the demo.
 */

import type React from "react"
import {
  Building2,
  ChartColumn,
  LayoutDashboard,
  Settings,
  ShieldCheck,
  Sparkles,
} from "lucide-react"
import { ThemeToggle } from "@/components/theme-toggle"
import { AppHeader } from "@/components/app-header"

// Only what actually works appears here. An earlier version listed Portfolio,
// Assets, Reporting, Data quality and Settings as muted placeholders to suggest
// a wider product; that was a mistake. In a live demo an unclickable nav item
// reads as a broken app, not as scope.
const NAV = [
  { label: "Copilot", icon: Sparkles, active: true },
] as const

/** Geometric mark plus wordmark. Not a reproduction of the real logo. */
function Wordmark() {
  return (
    <div className="flex items-center gap-2.5 px-3 py-1">
      <span
        aria-hidden
        className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-brand-teal"
      >
        <span className="h-3 w-3 rounded-[3px] bg-brand-teal-bright" />
      </span>
      <span className="hidden text-lg font-semibold tracking-tight text-brand-teal-darkest md:inline dark:text-brand-teal-bright">
        Deepki
      </span>
    </div>
  )
}

function NavRow({
  label,
  icon: Icon,
  active,
}: {
  label: string
  icon: React.ComponentType<{ className?: string }>
  active: boolean
}) {
  const base =
    "flex items-center gap-3 rounded-md px-3 py-2 text-sm md:justify-start justify-center"

  if (!active) {
    return (
      <span
        aria-disabled="true"
        title="Not part of this demo"
        className={`${base} cursor-default text-muted-foreground/70 select-none`}
      >
        <Icon className="h-4 w-4 shrink-0" />
        <span className="hidden md:inline">{label}</span>
      </span>
    )
  }

  return (
    <a
      href="#copilot"
      aria-current="page"
      className={`${base} bg-secondary font-medium text-secondary-foreground`}
    >
      <Icon className="h-4 w-4 shrink-0" />
      <span className="hidden md:inline">{label}</span>
    </a>
  )
}

export function AppShell({
  title = "Portfolio Copilot",
  subtitle = "Ask about CRREM pathway exposure, stranded floor area and retrofit priorities.",
  actions,
  children,
}: {
  title?: string
  subtitle?: string
  /** Right-hand slot in the top bar. The tenant selector lands here. */
  actions?: React.ReactNode
  children: React.ReactNode
}) {
  return (
    <div className="flex min-h-screen bg-muted">
      {/* Left rail. Collapses to icons below md rather than becoming a drawer. */}
      <aside className="flex w-16 shrink-0 flex-col border-r border-border bg-background py-4 md:w-60">
        <Wordmark />

        <nav aria-label="Sections" className="mt-6 flex flex-col gap-1 px-2">
          {NAV.map((item) => (
            <NavRow key={item.label} {...item} />
          ))}
        </nav>

        {/* pb clears the Next dev-tools badge, which is pinned bottom-left. */}
        <div className="mt-auto flex flex-col items-center gap-2 px-2 pt-6 pb-12 md:items-start md:px-3">
          <p className="hidden text-xs leading-snug text-muted-foreground md:block">
            Powered by
            <br />
            Snowflake Cortex
          </p>
          <ThemeToggle />
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <div className="border-b border-border bg-background px-4 py-4 md:px-8">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <AppHeader title={title} subtitle={subtitle} />
            {actions ? <div className="shrink-0">{actions}</div> : null}
          </div>
        </div>

        <main id="copilot" className="min-w-0 flex-1 px-4 py-6 md:px-8 md:py-8">
          <div className="mx-auto w-full max-w-6xl space-y-6">{children}</div>
        </main>
      </div>
    </div>
  )
}
