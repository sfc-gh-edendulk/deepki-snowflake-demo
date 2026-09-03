/**
 * Cortex Agent proxy.
 *
 * POST /api/agent  { messages: AgentMessage[], stream?: boolean }
 *
 * The browser never sees the Snowflake PAT: it posts the conversation here and
 * this route forwards it to the agent's `:run` endpoint.
 *
 * Two modes:
 *   - Streaming (default). We ask the agent for server-sent events, translate its
 *     event stream into a much smaller protocol of our own, and pipe that to the
 *     browser as it arrives. The panel then shows thinking, SQL and tables while
 *     the agent is still working instead of waiting on one long request.
 *   - Non-streaming (`{ stream: false }`). Unchanged from the original route: one
 *     JSON response with text, tables, charts and toolsUsed. Kept because it is
 *     the shape used for curl testing.
 *
 * The agent plans, writes SQL, runs it and summarises, so a single call routinely
 * takes 30-90 seconds — hence the long abort timeout rather than the platform default.
 */

import { NextResponse } from "next/server"
import { getSnowflakeBaseUrl } from "@/lib/snowflake"
import { AGENT } from "@/lib/constants"

export const dynamic = "force-dynamic"
/** Agent calls can run to ~90s; keep the platform from cutting the route short. */
export const maxDuration = 300

/** How long to wait on the agent before giving up (ms). */
const AGENT_TIMEOUT_MS = 180_000

/** One turn of the conversation, in the shape the agent API expects. */
export interface AgentMessage {
  role: "user" | "assistant"
  content: { type: string; text?: string }[]
}

/** A result set the agent returned, already flattened for rendering. */
export interface AgentTable {
  title: string | null
  columns: string[]
  rows: unknown[][]
}

/** A chart the agent returned. `spec` is the parsed Vega-Lite spec. */
export interface AgentChart {
  title: string | null
  spec: Record<string, unknown>
}

/** One SQL statement the agent wrote and ran, shown to the user for scrutiny. */
export interface AgentSql {
  sql: string
  queryId: string | null
}

/**
 * A document a Cortex Search tool retrieved. The search service indexes columns
 * named `doc_title`, `doc_type`, `doc_source`, `doc_id` and `related_asset_id`,
 * so those are the fields we look for.
 */
export interface AgentCitation {
  docId: string | null
  title: string | null
  docType: string | null
  source: string | null
  relatedAssetId: string | null
  text: string | null
}

export interface AgentResponse {
  raw: unknown
  text: string
  tables: AgentTable[]
  charts: AgentChart[]
  toolsUsed: string[]
}

/**
 * Shape of a single `content` entry in the agent response. Deliberately loose:
 * the agent may add item types, and an unknown type must not break parsing.
 */
interface ContentItem {
  type?: string
  text?: string
  tool_use?: { name?: string }
  table?: {
    title?: string
    result_set?: ResultSet
  }
  chart?: { title?: string; chart_spec?: string }
}

interface ResultSet {
  resultSetMetaData?: { rowType?: { name?: string }[] }
  data?: unknown[][]
}

// --- Tenant personas ---

/**
 * Map a demo persona to the PAT it authenticates with.
 *
 * Each PAT belongs to a *different* Snowflake user, and that is the whole point:
 * a Cortex Agent resolves privileges from the querying user's DEFAULT role, not
 * from any role the session happens to set. So tenant isolation cannot be done by
 * switching roles on one shared user — the tenant PAT has to belong to a user
 * whose default role already is that tenant's role. The row access policy then
 * filters every answer the agent produces, including the SQL it writes itself.
 *
 * An unknown persona, or one whose PAT is not configured, falls back to the
 * internal PAT so the demo degrades to "all clients" rather than failing.
 */
function patForTenant(tenant: string | null): { pat: string | undefined; resolved: string } {
  switch (tenant) {
    case "rhenus":
      if (process.env.SNOWFLAKE_PAT_RHENUS) {
        return { pat: process.env.SNOWFLAKE_PAT_RHENUS, resolved: "rhenus" }
      }
      break
    case "vaneau":
      if (process.env.SNOWFLAKE_PAT_VANEAU) {
        return { pat: process.env.SNOWFLAKE_PAT_VANEAU, resolved: "vaneau" }
      }
      break
  }
  return { pat: process.env.SNOWFLAKE_PAT, resolved: "internal" }
}

// --- Shared parsing ---

function parseResultSet(title: string | null, resultSet: ResultSet | undefined): AgentTable | null {
  if (!resultSet) return null
  const columns = (resultSet.resultSetMetaData?.rowType ?? [])
    .map((c) => c.name ?? "")
    .filter((n) => n !== "")
  const rows = Array.isArray(resultSet.data) ? resultSet.data : []
  return { title, columns, rows }
}

function parseTable(item: ContentItem): AgentTable | null {
  return parseResultSet(item.table?.title ?? null, item.table?.result_set)
}

function parseChartSpec(title: string | null, spec: unknown): AgentChart | null {
  if (typeof spec !== "string") return null
  try {
    const parsed = JSON.parse(spec) as Record<string, unknown>
    return { title, spec: parsed }
  } catch {
    // A malformed spec is not worth failing the whole answer over.
    console.warn("Agent route: could not parse chart_spec as JSON, skipping chart")
    return null
  }
}

function parseChart(item: ContentItem): AgentChart | null {
  return parseChartSpec(item.chart?.title ?? null, item.chart?.chart_spec)
}

/** First non-empty string found at any of `keys` on a loose object. */
function pickString(obj: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = obj[key]
    if (typeof value === "string" && value.trim() !== "") return value
  }
  return null
}

/**
 * Pull citations out of a Cortex Search tool result. The shape varies between
 * search services and agent versions, so we walk the plausible containers
 * (`searchResults`, `results`, `documents`, or a bare array) rather than
 * insisting on one layout.
 */
function citationsFromToolResult(content: unknown): AgentCitation[] {
  const docs: Record<string, unknown>[] = []

  const collect = (value: unknown) => {
    if (Array.isArray(value)) {
      for (const entry of value) {
        if (entry && typeof entry === "object") docs.push(entry as Record<string, unknown>)
      }
    }
  }

  const visit = (value: unknown) => {
    if (!value || typeof value !== "object") return
    if (Array.isArray(value)) {
      collect(value)
      return
    }
    const obj = value as Record<string, unknown>
    // A search tool_result carries its payload under `json`; some versions nest
    // the documents one level deeper again under searchResults/results/documents.
    for (const key of ["searchResults", "results", "documents", "citations"]) {
      collect(obj[key])
    }
    if (obj.json) visit(obj.json)
  }

  if (Array.isArray(content)) {
    for (const entry of content) visit(entry)
  } else {
    visit(content)
  }

  const out: AgentCitation[] = []
  for (const doc of docs) {
    const citation: AgentCitation = {
      docId: pickString(doc, ["doc_id", "DOC_ID", "docId", "source_id"]),
      title: pickString(doc, ["doc_title", "DOC_TITLE", "docTitle", "title"]),
      docType: pickString(doc, ["doc_type", "DOC_TYPE", "docType"]),
      source: pickString(doc, ["doc_source", "DOC_SOURCE", "docSource", "source"]),
      relatedAssetId: pickString(doc, ["related_asset_id", "RELATED_ASSET_ID", "relatedAssetId"]),
      text: pickString(doc, ["doc_text", "DOC_TEXT", "text", "chunk", "content"]),
    }
    // Anything with no title and no id is not worth showing as a citation.
    if (citation.title || citation.docId) out.push(citation)
  }
  return out
}

/** Every SQL statement mentioned in a tool_result payload, with its query id. */
function sqlFromToolResult(content: unknown): AgentSql[] {
  const out: AgentSql[] = []
  const visit = (value: unknown) => {
    if (!value || typeof value !== "object") return
    if (Array.isArray(value)) {
      for (const entry of value) visit(entry)
      return
    }
    const obj = value as Record<string, unknown>
    if (typeof obj.sql === "string" && obj.sql.trim() !== "") {
      const queryId = pickString(obj, ["query_id", "queryId"])
      out.push({ sql: obj.sql, queryId })
    }
    if (obj.json) visit(obj.json)
  }
  visit(content)
  return out
}

// --- Streaming ---

/** The simplified event names this route emits to the browser. */
type ClientEvent =
  | "status"
  | "thinking"
  | "text"
  | "tool"
  | "sql"
  | "table"
  | "chart"
  | "citation"
  | "done"
  | "error"

function sseFrame(event: ClientEvent, data: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`
}

/** Identity for a table, so the final payload does not re-emit a streamed one. */
function tableKey(table: AgentTable): string {
  return `${table.title ?? ""}::${table.columns.join("|")}::${table.rows.length}`
}

interface UpstreamFrame {
  event: string
  data: string
}

/**
 * Split raw SSE text into complete frames, returning the leftover tail.
 *
 * SSE frames are separated by a blank line, and a single network chunk gives no
 * guarantee of alignment with that boundary: one chunk can hold three frames, or
 * half of one `data:` line. So we only cut at a blank line and hand whatever
 * follows the last blank line back to the caller to prepend to the next chunk.
 * `data:` lines within a frame are concatenated, which is what the spec says and
 * also what happens when the agent emits a long JSON payload.
 */
function drainFrames(buffer: string): { frames: UpstreamFrame[]; rest: string } {
  const frames: UpstreamFrame[] = []
  // Normalise CRLF so the blank-line split below has one thing to look for.
  const normalised = buffer.replace(/\r\n/g, "\n")
  const parts = normalised.split("\n\n")
  // The final part is either an incomplete frame or an empty string; either way
  // it is not safe to parse yet.
  const rest = parts.pop() ?? ""

  for (const part of parts) {
    let event = "message"
    const dataLines: string[] = []
    for (const line of part.split("\n")) {
      if (line.startsWith("event:")) {
        event = line.slice(6).trim()
      } else if (line.startsWith("data:")) {
        dataLines.push(line.slice(5).trimStart())
      }
      // Comment lines (":" keep-alives) and unknown fields are ignored.
    }
    if (dataLines.length > 0) frames.push({ event, data: dataLines.join("") })
  }

  return { frames, rest }
}

/**
 * Translate the agent's SSE stream into our own, smaller protocol.
 *
 * Deliberately forgiving: an event type we do not know, or a `data:` payload that
 * is not valid JSON, is skipped rather than allowed to abort the answer. The one
 * thing we guarantee is that exactly one `done` is emitted at the end.
 */
function transformAgentStream(upstream: ReadableStream<Uint8Array>): ReadableStream<Uint8Array> {
  const decoder = new TextDecoder()
  const encoder = new TextEncoder()
  const reader = upstream.getReader()

  let buffer = ""
  // Deduplication across the whole turn: the same SQL arrives on both tool_use
  // and tool_result, and the same document can be retrieved more than once.
  const seenSql = new Set<string>()
  const seenDocs = new Set<string>()
  const seenTools = new Set<string>()
  const seenTables = new Set<string>()
  const seenCharts = new Set<string>()
  // Whether any text delta arrived, which decides if the final payload has to
  // supply the prose itself.
  let sawTextDelta = false

  // One long-lived read loop rather than a chunk-per-`pull`. A large upstream
  // frame (the semantic model in a tool_result runs to megabytes) arrives over
  // many chunks, and a `pull` that returns having enqueued nothing — because no
  // frame was complete yet — is treated as end-of-stream once Next.js adapts this
  // to a Node stream. Looping inside `start` removes that ambiguity.
  return new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (event: ClientEvent, data: unknown) => {
        controller.enqueue(encoder.encode(sseFrame(event, data)))
      }

      const emitSql = (sql: string, queryId: string | null) => {
        const key = `${sql}::${queryId ?? ""}`
        if (seenSql.has(key) || sql.trim() === "") return
        // Also suppress the same statement arriving a second time with a query id
        // attached, which is the usual tool_use → tool_result sequence.
        if (queryId && seenSql.has(`${sql}::`)) seenSql.delete(`${sql}::`)
        else if (!queryId && [...seenSql].some((k) => k.startsWith(`${sql}::`))) return
        seenSql.add(key)
        emit("sql", { sql, queryId })
      }

      const handleFrame = (frame: UpstreamFrame) => {
        if (frame.data === "[DONE]") return

        let payload: Record<string, unknown>
        try {
          payload = JSON.parse(frame.data) as Record<string, unknown>
        } catch {
          return
        }

        switch (frame.event) {
          case "response.status":
            emit("status", {
              status: typeof payload.status === "string" ? payload.status : null,
              message: typeof payload.message === "string" ? payload.message : null,
            })
            break

          case "response.thinking.delta":
            if (typeof payload.text === "string") emit("thinking", { text: payload.text })
            break

          case "response.text.delta":
            if (typeof payload.text === "string") {
              sawTextDelta = true
              emit("text", { text: payload.text })
            }
            break

          case "response.tool_use": {
            const name = typeof payload.name === "string" ? payload.name : null
            if (name && !seenTools.has(name)) {
              seenTools.add(name)
              emit("tool", { name })
            }
            const input = payload.input
            if (input && typeof input === "object") {
              const sql = (input as Record<string, unknown>).sql
              if (typeof sql === "string") emitSql(sql, null)
            }
            break
          }

          case "response.tool_result": {
            const name = typeof payload.name === "string" ? payload.name : null
            if (name && !seenTools.has(name)) {
              seenTools.add(name)
              emit("tool", { name })
            }
            for (const found of sqlFromToolResult(payload.content)) {
              emitSql(found.sql, found.queryId)
            }
            for (const citation of citationsFromToolResult(payload.content)) {
              const key = citation.docId ?? citation.title ?? ""
              if (key === "" || seenDocs.has(key)) continue
              seenDocs.add(key)
              emit("citation", citation)
            }
            break
          }

          case "response.table": {
            const table = parseResultSet(
              typeof payload.title === "string" ? payload.title : null,
              payload.result_set as ResultSet | undefined,
            )
            if (table && !seenTables.has(tableKey(table))) {
              seenTables.add(tableKey(table))
              emit("table", table)
            }
            break
          }

          case "response.chart": {
            const chart = parseChartSpec(
              typeof payload.title === "string" ? payload.title : null,
              payload.chart_spec,
            )
            if (chart && !seenCharts.has(JSON.stringify(chart.spec))) {
              seenCharts.add(JSON.stringify(chart.spec))
              emit("chart", chart)
            }
            break
          }

          case "response": {
            // The final aggregated payload is authoritative: it is the answer the
            // agent stands behind. The deltas have normally already streamed the
            // prose, so we only fill gaps here — the whole text if no delta ever
            // arrived, plus any table, chart, tool or SQL the deltas missed. The
            // dedupe sets above make the overlap a no-op in the common case.
            const content = Array.isArray(payload.content)
              ? (payload.content as ContentItem[])
              : []

            if (!sawTextDelta) {
              const finalText = content
                .filter((item) => item.type === "text" && typeof item.text === "string")
                .map((item) => item.text as string)
                .join("\n\n")
              if (finalText !== "") emit("text", { text: finalText })
            }

            for (const item of content) {
              const name = item.tool_use?.name
              if (typeof name === "string" && name !== "" && !seenTools.has(name)) {
                seenTools.add(name)
                emit("tool", { name })
              }
              if (item.type === "table") {
                const table = parseTable(item)
                if (table && !seenTables.has(tableKey(table))) {
                  seenTables.add(tableKey(table))
                  emit("table", table)
                }
              }
              if (item.type === "chart") {
                const chart = parseChart(item)
                if (chart && !seenCharts.has(JSON.stringify(chart.spec))) {
                  seenCharts.add(JSON.stringify(chart.spec))
                  emit("chart", chart)
                }
              }
            }
            break
          }

          case "error":
            emit("error", {
              message:
                typeof payload.message === "string"
                  ? payload.message
                  : "The agent reported an error.",
              code: typeof payload.code === "string" ? payload.code : null,
            })
            break

          default:
            // Unknown event type: ignore.
            break
        }
      }

      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          buffer += decoder.decode(value, { stream: true })
          const { frames, rest } = drainFrames(buffer)
          buffer = rest
          for (const frame of frames) handleFrame(frame)
        }
        // Flush any trailing frame that arrived without its blank-line terminator.
        const tail = drainFrames(buffer + "\n\n")
        for (const frame of tail.frames) handleFrame(frame)
        emit("done", {})
        controller.close()
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e)
        emit("error", { message: `Agent stream failed: ${msg}`, code: null })
        emit("done", {})
        controller.close()
      }
    },
    cancel() {
      void reader.cancel()
    },
  })
}

/** SSE response headers. `no-transform` stops proxies buffering the stream. */
const SSE_HEADERS = {
  "Content-Type": "text/event-stream; charset=utf-8",
  "Cache-Control": "no-cache, no-transform",
  Connection: "keep-alive",
  "X-Accel-Buffering": "no",
} as const

/** A one-shot SSE stream carrying a single error, then done. */
function errorStream(message: string): Response {
  const encoder = new TextEncoder()
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(sseFrame("error", { message, code: null })))
      controller.enqueue(encoder.encode(sseFrame("done", {})))
      controller.close()
    },
  })
  return new Response(stream, { headers: SSE_HEADERS })
}

export async function POST(request: Request) {
  const baseUrl = getSnowflakeBaseUrl()
  if (!baseUrl) {
    return NextResponse.json(
      {
        error:
          "No Snowflake account URL. Set SNOWFLAKE_ACCOUNT_URL (or SNOWFLAKE_HOST) in .env.local.",
      },
      { status: 500 },
    )
  }

  let messages: AgentMessage[]
  let wantsStream = true
  try {
    const body = (await request.json()) as { messages?: AgentMessage[]; stream?: boolean }
    if (!Array.isArray(body.messages) || body.messages.length === 0) {
      return NextResponse.json(
        { error: "Request body must contain a non-empty `messages` array." },
        { status: 400 },
      )
    }
    messages = body.messages
    if (body.stream === false) wantsStream = false
  } catch {
    return NextResponse.json({ error: "Request body is not valid JSON." }, { status: 400 })
  }

  const tenant = request.headers.get("X-Demo-Tenant")
  const { pat, resolved } = patForTenant(tenant)
  if (!pat) {
    return NextResponse.json(
      { error: "SNOWFLAKE_PAT is not set. See README → Creating a PAT." },
      { status: 500 },
    )
  }

  const url =
    `${baseUrl}/api/v2/databases/${AGENT.database}` +
    `/schemas/${AGENT.schema}/agents/${AGENT.name}:run`

  const startedAt = Date.now()

  const headers: Record<string, string> = {
    Authorization: `Bearer ${pat}`,
    "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
    "Content-Type": "application/json",
    Accept: wantsStream ? "text/event-stream" : "application/json",
  }

  let res: Response
  try {
    res = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify({ messages, stream: wantsStream }),
      signal: AbortSignal.timeout(AGENT_TIMEOUT_MS),
    })
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error(`Agent route: request failed after ${Date.now() - startedAt}ms:`, msg)
    if (wantsStream) return errorStream(`Agent request failed: ${msg}`)
    return NextResponse.json({ error: `Agent request failed: ${msg}` }, { status: 502 })
  }

  if (!res.ok) {
    const detail = await res.text().catch(() => "")
    console.error(
      `Agent route: ${res.status} ${res.statusText} after ${Date.now() - startedAt}ms — ${detail}`,
    )
    if (wantsStream) return errorStream(`${res.status} ${detail}`)
    return NextResponse.json({ error: `${res.status} ${detail}` }, { status: 502 })
  }

  if (wantsStream) {
    if (!res.body) return errorStream("The agent returned an empty response body.")
    console.log(`Agent route: streaming as tenant=${resolved}`)
    return new Response(transformAgentStream(res.body), { headers: SSE_HEADERS })
  }

  // --- Non-streaming path: unchanged JSON contract ---

  const raw = (await res.json()) as { content?: ContentItem[] }
  const content = Array.isArray(raw.content) ? raw.content : []

  const text = content
    .filter((item) => item.type === "text" && typeof item.text === "string")
    .map((item) => item.text as string)
    .join("\n\n")

  const tables = content
    .filter((item) => item.type === "table")
    .map(parseTable)
    .filter((t): t is AgentTable => t !== null)

  const charts = content
    .filter((item) => item.type === "chart")
    .map(parseChart)
    .filter((c): c is AgentChart => c !== null)

  const toolsUsed = Array.from(
    new Set(
      content
        .filter((item) => item.type === "tool_use")
        .map((item) => item.tool_use?.name)
        .filter((n): n is string => typeof n === "string" && n !== ""),
    ),
  )

  console.log(
    `Agent route: ok in ${Date.now() - startedAt}ms tenant=${resolved} — ` +
      `${tables.length} table(s), ${charts.length} chart(s), tools=[${toolsUsed.join(", ")}]`,
  )

  const payload: AgentResponse = { raw, text, tables, charts, toolsUsed }
  return NextResponse.json(payload)
}
