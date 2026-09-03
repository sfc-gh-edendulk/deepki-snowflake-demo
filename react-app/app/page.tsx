import { AppShell } from "@/components/app-shell"
import { KpiStrip } from "@/components/kpi-strip"
import { CopilotPanel } from "@/components/copilot-panel"

// Required: Snowflake is not reachable during docker build.
export const dynamic = "force-dynamic"

export default function Home() {
  return (
    <AppShell>
      <KpiStrip />
      <CopilotPanel />
    </AppShell>
  )
}
