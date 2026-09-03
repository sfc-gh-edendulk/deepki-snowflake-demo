/**
 * AppHeader — the section title block used by the shell's top bar.
 *
 * This used to be the whole navigation bar. AppShell owns navigation now, so
 * this is just the heading pair; it stays a component because the shell and
 * anything else framing a section can reuse it.
 */
export function AppHeader({
  title = "Portfolio Copilot",
  subtitle,
}: {
  title?: string
  subtitle?: string
}) {
  return (
    <div className="min-w-0">
      <h1 className="text-xl font-semibold tracking-tight text-foreground md:text-2xl">
        {title}
      </h1>
      {subtitle && (
        <p className="mt-1 max-w-2xl text-sm text-muted-foreground">{subtitle}</p>
      )}
    </div>
  )
}
