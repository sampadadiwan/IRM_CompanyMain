import { Controller } from "@hotwired/stimulus"

// Export PowerPoint (assistants/_thread): every answer in the conversation as slides, titled with the
// question it answers. An answer is read as a list of pieces in order — headings, paragraphs, lists, Key
// figures, Verdict, Checks, tables, charts (the markup AiChatHelper#ai_answer_html draws) — and each piece
// is placed below the last at a height measured from its wrapped lines. A piece that does not fit starts
// a continuation slide; a long table is split across slides with its header repeated. Charts get a slide
// of their own. Nothing is drawn on top of anything else.
//
// Slide geometry is in inches on the 13.33 × 7.5 widescreen layout.
const PAGE = { left: 0.5, width: 12.33, top: 0.35, bottom: 7.1 }
// Average character width as a share of the font size (Calibri-like fonts run ~0.5; a little extra
// keeps the estimate on the safe side, so a box is never shorter than its text).
const CHAR_WIDTH = 0.56
const LINE_HEIGHT = 1.3
const GAP = 0.14
const FONT = { title: 18, heading: 14, body: 11, table: 10, figure: 20, label: 10 }
// Elements whose content is laid out as blocks of their own.
const BLOCK_TAGS = new Set(["P", "DIV", "UL", "OL", "TABLE", "H1", "H2", "H3", "H4", "H5", "H6", "SECTION", "BLOCKQUOTE", "PRE", "LI"])

export default class extends Controller {
  static targets = ["responses"]

  async export() {
    let PptxGenJS
    try {
      const module = await import("pptxgenjs")
      PptxGenJS = module.default || module
    } catch (e) {
      console.error("[PptExportController] Failed to import pptxgenjs", e)
      alert("Failed to load PowerPoint generator library.")
      return
    }

    let pres
    try {
      pres = new PptxGenJS()
    } catch (e) {
      pres = PptxGenJS()
    }
    pres.layout = "LAYOUT_WIDE"
    this.pres = pres
    this.colours = this.themeColours()

    // H4 — the chat kit marks each answer (ai_chat/_answer) and its rendered body; a question
    // (ai_chat/_question) comes before its answer, so each answer is titled with the latest question.
    const messages = Array.from(this.responsesTarget.querySelectorAll(".aic-message"))
    let question = null
    let answered = 0
    for (const message of messages) {
      const questionEl = message.querySelector(".aic-question")
      if (questionEl) {
        question = questionEl.innerText.trim()
        continue
      }
      const body = message.querySelector("[data-ai-chat-answer-body]")
      if (!message.hasAttribute("data-ai-chat-answer") || !body) continue

      answered += 1
      const pieces = []
      this.collect(body, pieces)
      this.layoutAnswer(question || `Answer ${answered}`, pieces)
    }

    if (answered === 0) {
      alert("No assistant responses found to export.")
      return
    }

    const filename = `Assistant_Export_${new Date().toISOString().slice(0, 10)}.pptx`
    await pres.writeFile({ fileName: filename })
    console.log(`[PptExportController] Exported: ${filename}`)
  }

  // ── Reading an answer ───────────────────────────────────────────────────────────────────────────

  // Walks the answer's markup in order and appends one piece per thing a slide shows.
  collect(node, pieces) {
    for (const el of Array.from(node.children)) {
      // Verdict banner: its word and reason.
      if (el.hasAttribute("data-ai-chat-verdict")) {
        const label = el.querySelector("strong")?.innerText.trim() || ""
        const reason = el.innerText.trim().slice(label.length).replace(/^\s*[—–\-:.]?\s*/, "")
        pieces.push({ type: "verdict", tone: el.dataset.aiChatVerdict, label, text: reason })
        continue
      }
      // A chart (chart_renderer_controller) goes on its own slide as a picture of its canvas.
      const chart = el.matches('[data-controller*="chart-renderer"]') ? el : el.querySelector('[data-controller*="chart-renderer"]')
      if (chart) {
        const canvas = chart.querySelector("canvas")
        if (canvas) pieces.push({ type: "chart", canvas })
        continue
      }
      // Key figures: a row of stat cards → tiles of value and label.
      if (el.classList.contains("row") && el.querySelector(".stat-card-accent")) {
        const figures = Array.from(el.querySelectorAll(".stat-card-accent")).map(card => ({
          value: card.querySelector("h2, .fs-6")?.innerText.trim() || "",
          label: card.querySelector(".card-subtitle")?.innerText.trim() || ""
        }))
        pieces.push({ type: "figures", figures })
        continue
      }
      if (el.tagName === "TABLE") {
        const rows = this.extractTableData(el)
        if (rows.length > 0) pieces.push({ type: "table", rows })
        continue
      }
      // A section card: its header becomes a heading, then its body is read like the answer.
      if (el.classList.contains("card-header")) {
        const text = el.innerText.trim()
        if (text) pieces.push({ type: "heading", text })
        continue
      }
      if (/^H[1-6]$/.test(el.tagName)) {
        const text = el.innerText.trim()
        if (text) pieces.push({ type: "heading", text })
        continue
      }
      if (el.tagName === "UL" || el.tagName === "OL") {
        const items = Array.from(el.children).filter(li => li.tagName === "LI").map(li => ({
          // Checks mark each item pass or fail; ordinary lists have no mark.
          check: li.dataset.aiChatCheck || null,
          text: li.innerText.trim()
        })).filter(item => item.text)
        const numbered = el.tagName === "OL"
        if (items.length > 0) pieces.push({ type: "list", items, numbered })
        continue
      }
      // Anything that still holds blocks is a wrapper: read inside it. Otherwise it is text.
      const hasBlocks = Array.from(el.children).some(child => BLOCK_TAGS.has(child.tagName) || child.classList.contains("card"))
      if (hasBlocks) {
        this.collect(el, pieces)
      } else {
        const text = el.innerText.trim()
        if (text) pieces.push({ type: "text", text })
      }
    }
  }

  extractTableData(tableEl) {
    const data = []
    tableEl.querySelectorAll("tr").forEach(row => {
      const cells = Array.from(row.querySelectorAll("th, td")).map(cell => cell.innerText.trim())
      if (cells.length > 0) data.push(cells)
    })
    return data
  }

  // ── Placing an answer on slides ─────────────────────────────────────────────────────────────────

  // Starts the answer's first slide and places each piece, moving to a continuation slide whenever
  // the next piece does not fit in what is left of the current one.
  layoutAnswer(question, pieces) {
    this.question = question
    this.continued = false
    this.newSlide()

    // Pieces taller than a whole slide are split first, so every piece fits on some slide.
    const queue = pieces.flatMap(piece => this.split(piece))
    queue.forEach((piece, index) => {
      if (piece.type === "chart") return this.chartSlide(piece.canvas)
      if (piece.type === "table") return this.placeTable(piece.rows)

      const height = this.measure(piece)
      // A heading keeps its first line of content with it (no heading alone at a slide's foot).
      const next = queue[index + 1]
      const keep = piece.type === "heading" && next && next.type !== "chart" ? Math.min(this.measure(next), 0.7) + GAP : 0
      this.ensureRoom(height + keep)
      this.draw(piece, height)
      this.y += height + GAP
    })
  }

  // A list or paragraph taller than a slide's content area, halved until each part fits: lists by
  // items, text by sentences. Other pieces are returned as they are.
  split(piece) {
    const room = PAGE.bottom - this.contentTop()
    if (this.measure(piece) <= room) return [piece]
    if (piece.type === "list" && piece.items.length > 1) {
      const half = Math.ceil(piece.items.length / 2)
      return [...this.split({ ...piece, items: piece.items.slice(0, half) }),
              ...this.split({ ...piece, items: piece.items.slice(half) })]
    }
    if (piece.type === "text") {
      const sentences = piece.text.match(/[^.!?\n]+[.!?]*\s*|\n+/g) || [piece.text]
      if (sentences.length > 1) {
        const half = Math.ceil(sentences.length / 2)
        return [...this.split({ ...piece, text: sentences.slice(0, half).join("").trim() }),
                ...this.split({ ...piece, text: sentences.slice(half).join("").trim() })]
      }
    }
    return [piece]
  }

  // A new slide for the current answer: the question as its title ("(cont.)" after the first).
  newSlide() {
    this.slide = this.pres.addSlide()
    const title = this.truncate(this.question, 160) + (this.continued ? " (cont.)" : "")
    const height = this.textHeight(title, FONT.title, PAGE.width)
    this.slide.addText(title, this.textBox(PAGE.top, height, { fontSize: FONT.title, bold: true, color: "212529" }))
    this.y = PAGE.top + height + 0.25
    this.continued = true
  }

  // Moves to a continuation slide unless `height` fits below the current position.
  ensureRoom(height) {
    if (this.y + height > PAGE.bottom && this.y > this.contentTop()) this.newSlide()
  }

  contentTop() {
    return PAGE.top + this.textHeight(this.truncate(this.question, 160), FONT.title, PAGE.width) + 0.25
  }

  // How tall a piece is when drawn (inches).
  measure(piece) {
    switch (piece.type) {
      case "heading": return this.textHeight(piece.text, FONT.heading, PAGE.width)
      case "text": return this.textHeight(piece.text, FONT.body, PAGE.width)
      case "verdict": return this.textHeight(`${piece.label} — ${piece.text}`, FONT.body, PAGE.width - 0.4) + 0.2
      case "list": return piece.items.reduce((sum, item) => sum + this.textHeight(item.text, FONT.body, PAGE.width - 0.4), 0)
      case "figures": return this.figureRows(piece.figures).reduce((sum, row) => sum + row.height + GAP, 0) - GAP
      default: return 0
    }
  }

  draw(piece, height) {
    const y = this.y
    switch (piece.type) {
      case "heading":
        this.slide.addText(piece.text, this.textBox(y, height, { fontSize: FONT.heading, bold: true, color: "212529" }))
        break
      case "text":
        this.slide.addText(piece.text, this.textBox(y, height, { fontSize: FONT.body, color: "343A40" }))
        break
      case "verdict": {
        const colour = this.colours[{ mismatch: "danger", matches: "success" }[piece.tone] || "secondary"]
        this.slide.addShape(this.pres.shapes.RECTANGLE, {
          x: PAGE.left, y, w: PAGE.width, h: height, fill: { color: colour, transparency: 88 }, line: { color: colour, width: 1 }
        })
        this.slide.addText([
          { text: piece.label, options: { bold: true, color: colour } },
          { text: piece.text ? ` — ${piece.text}` : "", options: { color: "343A40" } }
        ], { ...this.textBox(y + 0.1, height - 0.2, { fontSize: FONT.body }), x: PAGE.left + 0.2, w: PAGE.width - 0.4 })
        break
      }
      case "list":
        this.drawList(piece, y, height)
        break
      case "figures":
        this.drawFigures(piece.figures, y)
        break
    }
  }

  // A list as one text box: bullets or numbers, Checks with ✓ / ✗ in their colours.
  drawList(piece, y, height) {
    const runs = piece.items.map((item, i) => {
      const last = i === piece.items.length - 1
      if (item.check) {
        const pass = item.check === "pass"
        return [
          { text: pass ? "✓  " : "✗  ", options: { bold: true, color: pass ? this.colours.success : this.colours.danger } },
          { text: item.text, options: { breakLine: !last } }
        ]
      }
      // Numbers are written out: pptxgenjs restarts its own numbering on every paragraph ("1. 1.").
      if (piece.numbered) return [{ text: `${i + 1}.  ${item.text}`, options: { breakLine: !last } }]
      return [{ text: item.text, options: { bullet: true, indentLevel: 0, breakLine: !last } }]
    }).flat()
    this.slide.addText(runs, { ...this.textBox(y, height, { fontSize: FONT.body, color: "343A40" }), x: PAGE.left + 0.2, w: PAGE.width - 0.2 })
  }

  // Key figures as tiles, up to four a row: value large, label underneath, an accent bar on top.
  figureRows(figures) {
    const rows = []
    for (let i = 0; i < figures.length; i += 4) {
      const row = figures.slice(i, i + 4)
      const width = (PAGE.width - GAP * 3) / 4
      const valueSize = row.some(f => f.value.length * FONT.figure * CHAR_WIDTH / 72 > width - 0.3) ? 14 : FONT.figure
      const labelHeight = Math.max(...row.map(f => this.textHeight(f.label, FONT.label, width - 0.3)))
      const valueHeight = Math.max(...row.map(f => this.textHeight(f.value, valueSize, width - 0.3)))
      rows.push({ figures: row, width, valueSize, valueHeight, labelHeight, height: 0.15 + valueHeight + labelHeight + 0.15 })
    }
    return rows
  }

  drawFigures(figures, top) {
    let y = top
    for (const row of this.figureRows(figures)) {
      row.figures.forEach((figure, i) => {
        const x = PAGE.left + i * (row.width + GAP)
        this.slide.addShape(this.pres.shapes.RECTANGLE, { x, y, w: row.width, h: row.height, fill: { color: "FFFFFF" }, line: { color: "DEE2E6", width: 1 } })
        this.slide.addShape(this.pres.shapes.RECTANGLE, { x, y, w: row.width, h: 0.05, fill: { color: this.colours.primary }, line: { type: "none" } })
        this.slide.addText(figure.value, { ...this.textBox(y + 0.15, row.valueHeight, { fontSize: row.valueSize, color: "212529" }), x: x + 0.15, w: row.width - 0.3 })
        this.slide.addText(figure.label, { ...this.textBox(y + 0.15 + row.valueHeight, row.labelHeight, { fontSize: FONT.label, color: this.colours.primary }), x: x + 0.15, w: row.width - 0.3 })
      })
      y += row.height + GAP
    }
  }

  // A table, split by rows across as many slides as it needs, with its header row on each part.
  placeTable(rows) {
    const columns = Math.max(...rows.map(r => r.length))
    const colWidth = PAGE.width / columns
    const rowHeight = row => Math.max(...row.map(cell => this.textHeight(cell, FONT.table, colWidth - 0.15))) + 0.06
    const [header, ...body] = rows
    const headerHeight = rowHeight(header)

    let index = 0
    // At least the header and one row must fit, or the table starts on a new slide.
    this.ensureRoom(headerHeight + (body.length ? rowHeight(body[0]) : 0))
    do {
      const part = [header]
      const heights = [headerHeight]
      let used = headerHeight
      while (index < body.length && (part.length === 1 || this.y + used + rowHeight(body[index]) <= PAGE.bottom)) {
        const height = rowHeight(body[index])
        part.push(body[index])
        heights.push(height)
        used += height
        index += 1
      }
      this.slide.addTable(part.map((row, r) => row.map(cell => ({
        text: cell,
        options: r === 0 ? { bold: true, fill: { color: "F1F3F5" } } : {}
      }))), {
        x: PAGE.left, y: this.y, w: PAGE.width, colW: Array(columns).fill(colWidth), rowH: heights,
        fontSize: FONT.table, color: "343A40", valign: "middle", margin: 0.05,
        border: { type: "solid", color: "DEE2E6", pt: 1 }, autoPage: false
      })
      this.y += used + GAP
      if (index < body.length) this.newSlide()
    } while (index < body.length)
  }

  // A chart on its own slide, as large as fits with its aspect ratio kept; the answer then continues
  // on a fresh slide.
  chartSlide(canvas) {
    if (!canvas.width || !canvas.height) return
    let data
    try {
      data = canvas.toDataURL("image/png")
    } catch (e) {
      console.warn("[PptExportController] Failed to capture chart canvas", e)
      return
    }
    if (!data || data === "data:,") return

    if (this.y > this.contentTop()) this.newSlide()
    const maxW = PAGE.width
    const maxH = PAGE.bottom - this.y
    const ratio = canvas.width / canvas.height
    const w = Math.min(maxW, maxH * ratio)
    const h = w / ratio
    this.slide.addImage({ data, x: PAGE.left + (maxW - w) / 2, y: this.y, w, h })
    this.y = PAGE.bottom
  }

  // ── Measuring ───────────────────────────────────────────────────────────────────────────────────

  // Height (inches) of text at a font size wrapped to a width: its lines, each at LINE_HEIGHT.
  textHeight(text, fontSize, width) {
    const perLine = Math.max(1, Math.floor((width * 72) / (fontSize * CHAR_WIDTH)))
    const lines = String(text).split("\n").reduce((sum, line) => sum + Math.max(1, Math.ceil(line.length / perLine)), 0)
    return (lines * fontSize * LINE_HEIGHT) / 72 + 0.06
  }

  // A text box with a fixed height and no padding, so what is drawn is what was measured.
  textBox(y, h, options) {
    return { x: PAGE.left, y, w: PAGE.width, h, margin: 0, valign: "top", fit: "none", ...options }
  }

  truncate(text, length) {
    return text.length > length ? `${text.slice(0, length - 1)}…` : text
  }

  // The page's theme colours as hex without "#" (pptxgenjs's form), with Bootstrap's defaults.
  themeColours() {
    const style = getComputedStyle(document.documentElement)
    const read = (name, fallback) => (style.getPropertyValue(`--bs-${name}`).trim() || fallback).replace("#", "").toUpperCase()
    return { primary: read("primary", "#0D6EFD"), success: read("success", "#198754"), danger: read("danger", "#DC3545"), secondary: read("secondary", "#6C757D") }
  }
}
