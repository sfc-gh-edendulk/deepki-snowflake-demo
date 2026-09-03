"use client"

/**
 * Renders a chart the agent asked for.
 *
 * The agent returns Vega-Lite specs, and this app ships recharts rather than a
 * Vega runtime, so we translate the small subset of Vega-Lite the agent actually
 * emits: one mark type, an x and y encoding, an optional colour encoding, and
 * inline data. Anything outside that subset returns null, and the panel falls
 * back to showing the underlying table — which is honest, and better than drawing
 * an approximation of a chart nobody specified.
 *
 * Nothing here throws. A spec we cannot read is a null, never an error boundary.
 */

import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Scatter,
  ScatterChart,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"

type Row = Record<string, unknown>

type MarkKind = "bar" | "line" | "area" | "scatter"

interface Encoding {
  field: string
  /** Vega-Lite type: quantitative, nominal, ordinal, temporal. */
  kind: string
}

interface Translated {
  mark: MarkKind
  x: Encoding
  y: Encoding
  colour: string | null
  rows: Row[]
  /** Bars run left-to-right when the categories sit on the y axis. */
  horizontal: boolean
}

/** "stranded_floor_area_m2" → "Stranded Floor Area M2". */
function humanise(field: string): string {
  return field
    .replace(/[_-]+/g, " ")
    .trim()
    .replace(/\b\w/g, (c) => c.toUpperCase())
}

function formatNumber(value: unknown): string {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value.toLocaleString(undefined, { maximumFractionDigits: 2 })
  }
  if (value === null || value === undefined) return "—"
  return String(value)
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

/** `mark` is either a bare string or `{ type: "bar", ... }`. */
function readMark(spec: Record<string, unknown>): MarkKind | null {
  const raw = typeof spec.mark === "string" ? spec.mark : asObject(spec.mark)?.type
  switch (raw) {
    case "bar":
      return "bar"
    case "line":
      return "line"
    case "area":
      return "area"
    case "point":
    case "circle":
      return "scatter"
    default:
      return null
  }
}

function readEncoding(encoding: Record<string, unknown>, channel: string): Encoding | null {
  const channelSpec = asObject(encoding[channel])
  if (!channelSpec) return null
  const field = channelSpec.field
  if (typeof field !== "string" || field === "") return null
  const kind = typeof channelSpec.type === "string" ? channelSpec.type : "quantitative"
  return { field, kind }
}

function isCategorical(kind: string): boolean {
  return kind === "nominal" || kind === "ordinal"
}

/**
 * Read a spec into the handful of facts recharts needs, or null if the spec is
 * not one we can draw faithfully.
 */
function translate(spec: Record<string, unknown>): Translated | null {
  const mark = readMark(spec)
  if (!mark) return null

  const encoding = asObject(spec.encoding)
  if (!encoding) return null

  const x = readEncoding(encoding, "x")
  const y = readEncoding(encoding, "y")
  if (!x || !y) return null

  const rawRows = asObject(spec.data)?.values
  if (!Array.isArray(rawRows) || rawRows.length === 0) return null
  const rows = rawRows.filter((r): r is Row => r !== null && typeof r === "object")
  if (rows.length === 0) return null

  const colourEncoding = readEncoding(encoding, "color")

  // Vega-Lite expresses a horizontal bar chart by putting the categories on y and
  // the measure on x, so that is what we detect rather than looking for an
  // explicit orientation property.
  const horizontal = isCategorical(y.kind) && !isCategorical(x.kind)

  let ordered = rows
  if (mark === "bar") {
    // Bars read best ranked. The measure is on whichever axis is not categorical.
    const measure = horizontal ? x.field : y.field
    ordered = [...rows].sort((a, b) => {
      const av = a[measure]
      const bv = b[measure]
      if (typeof av === "number" && typeof bv === "number") return bv - av
      return 0
    })
  }

  return { mark, x, y, colour: colourEncoding?.field ?? null, rows: ordered, horizontal }
}

/**
 * Series colours. The theme may define chart custom properties; if it does we use
 * them, and otherwise fall back to recharts' own default so this component never
 * hardcodes brand colour and never clashes with a theme applied elsewhere.
 */
const SERIES_COLOURS = [
  "var(--chart-1, #8884d8)",
  "var(--chart-2, #82ca9d)",
  "var(--chart-3, #ffc658)",
  "var(--chart-4, #ff7f50)",
  "var(--chart-5, #8dd1e1)",
]

const CHART_HEIGHT = 320

/**
 * Whether a spec can be drawn at all. The panel needs to know before rendering so
 * it can fall back to the table, and asking this is safer than calling the
 * component as a function to inspect its return value.
 */
export function canRenderAgentChart(spec: Record<string, unknown>): boolean {
  try {
    return translate(spec) !== null
  } catch {
    return false
  }
}

export function AgentChart({ spec }: { spec: Record<string, unknown> }) {
  let model: Translated | null = null
  try {
    model = translate(spec)
  } catch {
    // A spec shaped in a way we did not anticipate is a fallback, not a failure.
    model = null
  }
  if (!model) return null

  const { mark, x, y, colour, rows, horizontal } = model

  // Which field is the category and which is the measure. For a horizontal bar
  // chart these swap over, and recharts wants that expressed as layout="vertical"
  // with the category on the YAxis.
  const categoryField = horizontal ? y.field : x.field
  const measureField = horizontal ? x.field : y.field

  // Colour encoding turns into one series per distinct value; without it there is
  // a single series over the measure field.
  const seriesValues = colour
    ? Array.from(new Set(rows.map((r) => String(r[colour] ?? "")))).filter((v) => v !== "")
    : []

  const tooltip = (
    <Tooltip formatter={(value: unknown) => formatNumber(value)} labelFormatter={(l) => String(l)} />
  )
  const grid = <CartesianGrid strokeDasharray="3 3" />
  const legend = seriesValues.length > 1 ? <Legend /> : null

  /**
   * When a colour encoding is present the rows have to be pivoted: recharts draws
   * one series per data key, so each category needs one row holding a column per
   * series value.
   */
  const data: Row[] = colour
    ? Object.values(
        rows.reduce<Record<string, Row>>((acc, row) => {
          const key = String(row[categoryField] ?? "")
          acc[key] ??= { [categoryField]: row[categoryField] }
          acc[key][String(row[colour] ?? "")] = row[measureField]
          return acc
        }, {}),
      )
    : rows

  const dataKeys = seriesValues.length > 0 ? seriesValues : [measureField]

  const categoryAxis = horizontal ? (
    <YAxis dataKey={categoryField} type="category" width={140} tick={{ fontSize: 12 }} />
  ) : (
    <XAxis dataKey={categoryField} tick={{ fontSize: 12 }} />
  )
  const measureAxis = horizontal ? (
    <XAxis type="number" tick={{ fontSize: 12 }} />
  ) : (
    <YAxis tick={{ fontSize: 12 }} tickFormatter={(v: unknown) => formatNumber(v)} />
  )

  let chart: React.ReactElement
  switch (mark) {
    case "bar":
      chart = (
        <BarChart data={data} layout={horizontal ? "vertical" : "horizontal"}>
          {grid}
          {categoryAxis}
          {measureAxis}
          {tooltip}
          {legend}
          {dataKeys.map((key, i) => (
            <Bar key={key} dataKey={key} fill={SERIES_COLOURS[i % SERIES_COLOURS.length]} />
          ))}
        </BarChart>
      )
      break

    case "line":
      chart = (
        <LineChart data={data}>
          {grid}
          <XAxis dataKey={x.field} tick={{ fontSize: 12 }} />
          <YAxis tick={{ fontSize: 12 }} tickFormatter={(v: unknown) => formatNumber(v)} />
          {tooltip}
          {legend}
          {dataKeys.map((key, i) => (
            <Line
              key={key}
              type="monotone"
              dataKey={key}
              stroke={SERIES_COLOURS[i % SERIES_COLOURS.length]}
              dot={false}
            />
          ))}
        </LineChart>
      )
      break

    case "area":
      chart = (
        <AreaChart data={data}>
          {grid}
          <XAxis dataKey={x.field} tick={{ fontSize: 12 }} />
          <YAxis tick={{ fontSize: 12 }} tickFormatter={(v: unknown) => formatNumber(v)} />
          {tooltip}
          {legend}
          {dataKeys.map((key, i) => (
            <Area
              key={key}
              type="monotone"
              dataKey={key}
              stroke={SERIES_COLOURS[i % SERIES_COLOURS.length]}
              fill={SERIES_COLOURS[i % SERIES_COLOURS.length]}
              fillOpacity={0.25}
            />
          ))}
        </AreaChart>
      )
      break

    case "scatter":
      // Scatter needs both axes numeric, so we plot the raw rows rather than the
      // pivoted ones and let the colour encoding split them into series.
      chart = (
        <ScatterChart>
          {grid}
          <XAxis dataKey={x.field} type="number" name={humanise(x.field)} tick={{ fontSize: 12 }} />
          <YAxis dataKey={y.field} type="number" name={humanise(y.field)} tick={{ fontSize: 12 }} />
          {tooltip}
          {legend}
          {seriesValues.length > 0 ? (
            seriesValues.map((value, i) => (
              <Scatter
                key={value}
                name={value}
                data={rows.filter((r) => String(r[colour as string] ?? "") === value)}
                fill={SERIES_COLOURS[i % SERIES_COLOURS.length]}
              />
            ))
          ) : (
            <Scatter data={rows} fill={SERIES_COLOURS[0]} />
          )}
        </ScatterChart>
      )
      break
  }

  return (
    <div className="mt-3">
      <div style={{ width: "100%", height: CHART_HEIGHT }}>
        <ResponsiveContainer width="100%" height="100%">
          {chart}
        </ResponsiveContainer>
      </div>
      <p className="mt-1 text-center text-xs text-muted-foreground">
        {humanise(measureField)} by {humanise(categoryField)}
      </p>
    </div>
  )
}
