/**
 * [`controllers/chart_renderer_controller.js`](app/javascript/controllers/chart_renderer_controller.js:1)
 *
 * We intentionally parse the chart spec ourselves instead of relying on Stimulus
 * ObjectValue parsing because assistant-generated HTML may sometimes include
 * stray escaping (e.g., a trailing `\` before the closing quote), which causes
 * `JSON.parse` to fail.
 */
import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

/**
 * Returns the shortest prefix of `text` that forms a complete JSON object/array.
 *
 * This is more robust than trimming to `lastIndexOf("}")`/`lastIndexOf("]")`
 * because assistant-generated HTML can sometimes include trailing garbage like:
 * `{"a":1}}` or `{"a":1}"` which would otherwise break `JSON.parse`.
 */
function sliceToCompleteJson(text) {
  const t = (text || "").trim()
  if (!(t.startsWith("{") || t.startsWith("["))) return t

  const stack = []
  let inString = false
  let quoteChar = null
  let escaped = false

  for (let i = 0; i < t.length; i++) {
    const ch = t[i]

    if (inString) {
      if (escaped) {
        escaped = false
        continue
      }

      if (ch === "\\") {
        escaped = true
        continue
      }

      if (ch === quoteChar) {
        inString = false
        quoteChar = null
      }

      continue
    }

    if (ch === '"' || ch === "'") {
      inString = true
      quoteChar = ch
      continue
    }

    if (ch === "{") stack.push("}")
    else if (ch === "[") stack.push("]")
    else if (stack.length > 0 && ch === stack[stack.length - 1]) {
      stack.pop()
      if (stack.length === 0) return t.slice(0, i + 1)
    }
  }

  // If we couldn't find a balanced end, fall back to the whole string.
  return t
}

export default class extends Controller {
  static targets = ["canvas"]

  // Treat as string and parse ourselves (more robust than Stimulus ObjectValue)
  static values = { spec: String }

  connect() {
    try {
      const ctx = this.canvasTarget.getContext("2d")
      const spec = this.parseSpec()

      if (!spec) return
      this.chart = new Chart(ctx, spec)
    } catch (e) {
      console.error("Chart render failed", e)
    }
  }

  disconnect() {
    this.chart?.destroy()
  }

  parseSpec() {
    // Prefer Stimulus value if present, fall back to raw attribute.
    const raw =
      (typeof this.specValue === "string" && this.specValue.length > 0
        ? this.specValue
        : this.element.getAttribute("data-chart-renderer-spec-value")) || ""

    if (!raw) return null

    let text = raw.trim()

    // Note: When the assistant HTML is inserted into the DOM, the browser decodes
    // HTML entities in attribute values. So we typically receive plain JSON here.

    // Unescape if it looks JSON-stringified (do this BEFORE checking for wrapping quotes).
    // We’re looking for literal backslash-quote sequences: \".
    if (text.includes('\\\"')) text = text.replace(/\\"/g, '"')
    if (text.includes("\\n")) text = text.replace(/\\n/g, "\n")

    // Common failure mode: assistant outputs `...}\` before the closing quote.
    // Strip trailing backslashes that would appear after valid JSON.
    text = text.replace(/\\+$/g, "")

    // Another common failure mode: stray trailing quote after an otherwise-valid JSON blob.
    // Drop a single trailing quote if the string otherwise looks like JSON.
    if (
      (text.startsWith("{") || text.startsWith("[")) &&
      (text.endsWith('"') || text.endsWith("'"))
    ) {
      text = text.slice(0, -1)
    }

    // Another common mode: the whole JSON object got wrapped in quotes.
    // Example: "{\"type\":\"bar\",...}" (after unescaping becomes: "{"type":"bar",...}")
    if (
      (text.startsWith('"') && text.endsWith('"')) ||
      (text.startsWith("'") && text.endsWith("'"))
    ) {
      text = text.slice(1, -1)
    }

    // If there are extra characters AFTER valid JSON (common in LLM-generated HTML),
    // slice down to the first complete JSON object/array.
    text = sliceToCompleteJson(text)

    try {
      return JSON.parse(text)
    } catch (e) {
      console.error("Chart spec JSON.parse failed", e, { raw, cleaned: text })
      return null
    }
  }
}
