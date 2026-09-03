"use client"

/**
 * Portfolio Copilot — the chat panel.
 *
 * Every turn posts the full conversation to /api/agent, which forwards it to the
 * Cortex Agent. The agent decides which tools to use; the badges under each
 * answer report which ones it actually chose, so the panel shows the reasoning
 * path rather than just the prose.
 *
 * The route streams, so an answer builds up in place: status line, then thinking,
 * then the SQL the agent wrote, then tables and charts, then the prose. That
 * matters more than a progress counter — a data architect watching this wants to
 * see what the agent did, not how long it took.
 *
 * The tenant switcher is not decoration. Each persona authenticates with its own
 * PAT, belonging to a user whose default role is that tenant's role, so the row
 * access policy filters every answer including the SQL the agent writes itself.
 */

import { useRef, useState } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { AgentChart, canRenderAgentChart } from "@/components/agent-chart"
import type {
  AgentChart as AgentChartData,
  AgentCitation,
  AgentMessage,
  AgentSql,
  AgentTable,
} from "@/app/api/agent/route"

/** Questions that show the agent picking different tools for different work. */
const PRESETS = [
  "How much floor area is off its CRREM pathway in 2025, and how much subscription revenue sits with the most exposed clients?",
  "Which client drives the largest share of stranded floor area, and what is the pattern by sector and heating system?",
  "What retrofit actions do you recommend for Rhenus Immobilien's five worst assets, and who should I contact?",
]

/** The three demo identities. `internal` sees every client; the others do not. */
const TENANTS = [
  { id: "internal", label: "Deepki staff (all clients)", org: null },
  { id: "rhenus", label: "Rhenus Immobilien — Andrea Vogt", org: "Rhenus Immobilien" },
  { id: "vaneau", label: "Vaneau Asset Management — Paul Mercier", org: "Vaneau Asset Management" },
] as const

type TenantId = (typeof TENANTS)[number]["id"]

/** A turn as rendered on screen. Assistant turns carry the agent's artefacts. */
interface Turn {
  role: "user" | "assistant"
  text: string
  thinking?: string
  status?: string | null
  tables?: AgentTable[]
  charts?: AgentChartData[]
  sql?: AgentSql[]
  citations?: AgentCitation[]
  toolsUsed?: string[]
  isError?: boolean
  streaming?: boolean
}

/** Turns on screen back into the wire format the agent expects. */
function toAgentMessages(turns: Turn[]): AgentMessage[] {
  return turns
    .filter((t) => !t.isError)
    .map((t) => ({
      role: t.role,
      content: [{ type: "text", text: t.text }],
    }))
}

function cellText(value: unknown): string {
  if (value === null || value === undefined) return "—"
  if (typeof value === "object") return JSON.stringify(value)
  return String(value)
}

function ResultTable({ table }: { table: AgentTable }) {
  if (table.columns.length === 0) return null
  return (
    <div className="mt-3 rounded-md border">
      {table.title && (
        <p className="border-b px-4 py-2 text-xs font-medium text-muted-foreground">
          {table.title}
        </p>
      )}
      <Table>
        <TableHeader>
          <TableRow>
            {table.columns.map((col) => (
              <TableHead key={col}>{col}</TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {table.rows.map((row, i) => (
            <TableRow key={i}>
              {table.columns.map((col, j) => (
                <TableCell key={col} className="tabular-nums">
                  {cellText(row[j])}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}

/**
 * A chart the agent asked for. AgentChart returns null for any spec it cannot
 * translate faithfully, in which case we say so — the table above it is then the
 * honest version of the same result.
 */
function ChartOrNotice({ chart }: { chart: AgentChartData }) {
  if (canRenderAgentChart(chart.spec)) {
    return (
      <div className="mt-3">
        {chart.title && (
          <p className="mb-1 text-xs font-medium text-muted-foreground">{chart.title}</p>
        )}
        <AgentChart spec={chart.spec} />
      </div>
    )
  }
  return (
    <p className="mt-2 text-xs italic text-muted-foreground">
      {chart.title ? `${chart.title} — ` : ""}
      Chart returned by the agent (Vega-Lite spec available)
    </p>
  )
}

/**
 * The SQL the agent wrote, collapsed by default. This is here because nobody
 * technical trusts a natural-language answer over a warehouse they cannot see
 * the query for.
 */
function SqlDisclosure({ statements }: { statements: AgentSql[] }) {
  if (statements.length === 0) return null
  return (
    <details className="mt-3 rounded-md border">
      <summary className="cursor-pointer px-4 py-2 text-xs font-medium text-muted-foreground">
        Show the {statements.length} {statements.length === 1 ? "query" : "queries"} the agent ran
      </summary>
      <div className="space-y-3 border-t px-4 py-3">
        {statements.map((statement, i) => (
          <div key={i}>
            {statement.queryId && (
              <p className="mb-1 font-mono text-[11px] text-muted-foreground">
                query_id {statement.queryId}
              </p>
            )}
            <pre className="overflow-x-auto whitespace-pre rounded bg-muted p-3 font-mono text-[11px] leading-relaxed">
              {statement.sql}
            </pre>
          </div>
        ))}
      </div>
    </details>
  )
}

/** Documents the search tool retrieved, so the prose can be traced to a source. */
function Citations({ citations }: { citations: AgentCitation[] }) {
  if (citations.length === 0) return null
  return (
    <div className="mt-3 rounded-md border px-4 py-3">
      <p className="text-xs font-medium text-muted-foreground">Grounded in</p>
      <ul className="mt-2 space-y-2">
        {citations.map((citation, i) => (
          <li key={citation.docId ?? i} className="text-xs">
            {citation.text ? (
              <details>
                <summary className="cursor-pointer">
                  <span className="font-medium">{citation.title ?? citation.docId}</span>
                  {citation.source && (
                    <span className="text-muted-foreground"> — {citation.source}</span>
                  )}
                </summary>
                <p className="mt-1 whitespace-pre-wrap text-muted-foreground">{citation.text}</p>
              </details>
            ) : (
              <>
                <span className="font-medium">{citation.title ?? citation.docId}</span>
                {citation.source && (
                  <span className="text-muted-foreground"> — {citation.source}</span>
                )}
              </>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

function AssistantTurn({ turn }: { turn: Turn }) {
  return (
    <div className="rounded-lg border bg-card p-4">
      {turn.streaming && turn.status && (
        <p className="mb-2 text-xs text-muted-foreground">{turn.status}</p>
      )}

      {/* Thinking is shown only while streaming: once the answer lands it is noise. */}
      {turn.streaming && turn.thinking && (
        <details className="mb-2">
          <summary className="cursor-pointer text-xs text-muted-foreground">
            Agent is reasoning…
          </summary>
          <p className="mt-1 whitespace-pre-wrap text-xs text-muted-foreground">{turn.thinking}</p>
        </details>
      )}

      {turn.text && (
        <p
          className={
            turn.isError
              ? "whitespace-pre-wrap text-sm text-destructive"
              : "whitespace-pre-wrap text-sm leading-relaxed"
          }
        >
          {turn.text}
        </p>
      )}

      {turn.sql && <SqlDisclosure statements={turn.sql} />}

      {turn.tables?.map((table, i) => (
        <ResultTable key={i} table={table} />
      ))}

      {turn.charts?.map((chart, i) => (
        <ChartOrNotice key={i} chart={chart} />
      ))}

      {turn.citations && <Citations citations={turn.citations} />}

      {turn.toolsUsed && turn.toolsUsed.length > 0 && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <span className="text-xs text-muted-foreground">Tools used</span>
          {turn.toolsUsed.map((tool) => (
            <Badge key={tool} variant="secondary" className="font-mono text-[11px]">
              {tool}
            </Badge>
          ))}
        </div>
      )}
    </div>
  )
}

export function CopilotPanel() {
  const [turns, setTurns] = useState<Turn[]>([])
  const [input, setInput] = useState("")
  const [pending, setPending] = useState(false)
  const [tenant, setTenant] = useState<TenantId>("internal")
  const [tenantNote, setTenantNote] = useState<string | null>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)

  const activeTenant = TENANTS.find((t) => t.id === tenant) ?? TENANTS[0]

  /**
   * Switching persona discards the conversation. The history was produced under a
   * different identity and a different row access policy, so replaying it to the
   * new one would be misleading — an answer about fifteen clients cannot be part
   * of a conversation a single tenant is having.
   */
  function switchTenant(next: TenantId) {
    if (next === tenant) return
    setTenant(next)
    setTurns([])
    const label = TENANTS.find((t) => t.id === next)?.label ?? next
    setTenantNote(`Conversation cleared — it belonged to the previous identity. Now acting as ${label}.`)
  }

  async function send() {
    const question = input.trim()
    if (!question || pending) return

    const nextTurns: Turn[] = [...turns, { role: "user", text: question }]
    setTurns(nextTurns)
    setInput("")
    setPending(true)
    setTenantNote(null)

    // The assistant turn is created empty and mutated as events arrive. Kept in a
    // local object so each event handler can update one field without having to
    // reason about the previous state shape.
    const live: Turn = {
      role: "assistant",
      text: "",
      thinking: "",
      status: "Agent is planning…",
      tables: [],
      charts: [],
      sql: [],
      citations: [],
      toolsUsed: [],
      streaming: true,
    }
    const flush = () => setTurns([...nextTurns, { ...live }])
    flush()

    try {
      const res = await fetch("/api/agent", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/event-stream",
          "X-Demo-Tenant": tenant,
        },
        body: JSON.stringify({ messages: toAgentMessages(nextTurns) }),
      })

      if (!res.ok || !res.body) {
        // A non-SSE failure still returns the JSON error shape from the route.
        let message = `Agent request failed (${res.status}).`
        try {
          const json = (await res.json()) as { error?: string }
          if (json.error) message = json.error
        } catch {
          // Body was not JSON; keep the status message.
        }
        setTurns([...nextTurns, { role: "assistant", text: message, isError: true }])
        return
      }

      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ""

      /**
       * Same blank-line framing as the route: a chunk boundary has nothing to do
       * with an event boundary, so we only parse up to the last blank line and
       * carry the remainder into the next read.
       */
      const handleFrame = (frame: string) => {
        let event = "message"
        const dataLines: string[] = []
        for (const line of frame.split("\n")) {
          if (line.startsWith("event:")) event = line.slice(6).trim()
          else if (line.startsWith("data:")) dataLines.push(line.slice(5).trimStart())
        }
        if (dataLines.length === 0) return

        let payload: Record<string, unknown>
        try {
          payload = JSON.parse(dataLines.join("")) as Record<string, unknown>
        } catch {
          return
        }

        switch (event) {
          case "status":
            live.status =
              typeof payload.message === "string"
                ? payload.message
                : typeof payload.status === "string"
                  ? payload.status
                  : live.status
            break
          case "thinking":
            if (typeof payload.text === "string") live.thinking = (live.thinking ?? "") + payload.text
            break
          case "text":
            if (typeof payload.text === "string") live.text += payload.text
            break
          case "tool":
            if (typeof payload.name === "string" && !live.toolsUsed!.includes(payload.name)) {
              live.toolsUsed!.push(payload.name)
            }
            break
          case "sql":
            if (typeof payload.sql === "string") {
              const incoming: AgentSql = {
                sql: payload.sql,
                queryId:
                  typeof payload.queryId === "string"
                    ? payload.queryId
                    : typeof payload.query_id === "string"
                      ? payload.query_id
                      : null,
              }
              // The same statement arrives twice: once as the analyst's own SQL on
              // tool_use, then again on tool_result fully expanded and carrying a
              // query id. Keep the richer one so the disclosure count reflects the
              // number of queries actually run, not the number of events.
              const squash = (a: string) => a.replace(/\s+/g, " ").replace(/;$/, "").trim()
              const already = live.sql!.findIndex(
                (s) =>
                  squash(s.sql).includes(squash(incoming.sql)) ||
                  squash(incoming.sql).includes(squash(s.sql)),
              )
              if (already === -1) live.sql!.push(incoming)
              else if (incoming.sql.length >= live.sql![already].sql.length) {
                live.sql![already] = incoming
              }
            }
            break
          case "table":
            live.tables!.push(payload as unknown as AgentTable)
            break
          case "chart":
            live.charts!.push(payload as unknown as AgentChartData)
            break
          case "citation":
            live.citations!.push(payload as unknown as AgentCitation)
            break
          case "error":
            live.isError = true
            live.text =
              typeof payload.message === "string" ? payload.message : "The agent reported an error."
            break
          case "done":
            live.streaming = false
            live.status = null
            break
        }
        flush()
      }

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const parts = buffer.replace(/\r\n/g, "\n").split("\n\n")
        buffer = parts.pop() ?? ""
        for (const part of parts) handleFrame(part)
      }

      live.streaming = false
      live.status = null
      if (!live.text.trim() && !live.isError) {
        live.text = "The agent returned no text for this question."
      }
      flush()
    } catch (e) {
      setTurns([
        ...nextTurns,
        {
          role: "assistant",
          text: e instanceof Error ? e.message : "Agent request failed.",
          isError: true,
        },
      ])
    } finally {
      setPending(false)
    }
  }

  function usePreset(preset: string) {
    setInput(preset)
    inputRef.current?.focus()
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Ask the portfolio agent</CardTitle>
        <p className="text-sm text-muted-foreground">
          The agent queries the portfolio itself: it writes its own SQL, picks its own tools, and
          cites the result sets it used. The answer streams as it works.
        </p>
      </CardHeader>

      <CardContent className="space-y-4">
        <div className="flex flex-wrap items-center gap-2">
          <label htmlFor="tenant" className="text-xs text-muted-foreground">
            Acting as
          </label>
          <select
            id="tenant"
            value={tenant}
            onChange={(e) => switchTenant(e.target.value as TenantId)}
            disabled={pending}
            className="rounded-md border border-input bg-background px-2 py-1 text-xs shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:opacity-50"
          >
            {TENANTS.map((t) => (
              <option key={t.id} value={t.id}>
                {t.label}
              </option>
            ))}
          </select>
        </div>

        {activeTenant.org && (
          <div className="rounded-md border-2 border-dashed border-destructive/60 bg-destructive/5 px-4 py-3">
            <p className="text-sm font-medium text-destructive">
              Acting as {activeTenant.org}. Row access policy is filtering every answer.
            </p>
            <p className="mt-1 text-xs text-muted-foreground">
              This persona authenticates with its own token, under a user whose default role is the
              tenant role. The agent resolves permissions from that role, so it cannot see another
              client&apos;s assets even if it writes the SQL itself.
            </p>
          </div>
        )}

        {tenantNote && <p className="text-xs text-muted-foreground">{tenantNote}</p>}

        <div className="flex flex-wrap gap-2">
          {PRESETS.map((preset, i) => (
            <Button
              key={preset}
              variant="outline"
              size="sm"
              onClick={() => usePreset(preset)}
              disabled={pending}
              className="max-w-full justify-start text-left"
              title={preset}
            >
              <span className="truncate">
                {i + 1}. {preset}
              </span>
            </Button>
          ))}
        </div>

        {turns.length > 0 && (
          <div className="space-y-3">
            {turns.map((turn, i) =>
              turn.role === "user" ? (
                <div key={i} className="rounded-lg bg-muted px-4 py-3">
                  <p className="whitespace-pre-wrap text-sm font-medium">{turn.text}</p>
                </div>
              ) : (
                <AssistantTurn key={i} turn={turn} />
              ),
            )}
          </div>
        )}

        <div className="space-y-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                e.preventDefault()
                void send()
              }
            }}
            rows={3}
            placeholder="Ask about stranded assets, CRREM pathways, client exposure or retrofit priorities…"
            disabled={pending}
            className="w-full resize-y rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:opacity-50"
          />
          <div className="flex items-center gap-3">
            <Button onClick={() => void send()} disabled={pending || input.trim() === ""}>
              {pending ? "Working…" : "Ask the agent"}
            </Button>
            <span className="text-xs text-muted-foreground">Cmd/Ctrl + Enter to send</span>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
