import { Controller } from "@hotwired/stimulus"
import mermaid from "mermaid"

// Renders the Fund Formula Dependencies diagram (see FundFormulaDependencyGraph#to_mermaid)
// and wires each node's mermaid "click ... call" directive to load that formula's
// details into the slide-out panel (see #fund_formula_detail_panel in
// dependencies.html.erb), whose open state is a single CSS class rather than a
// Bootstrap offcanvas -- see the stylesheet for why that matters across a Back
// navigation.
export default class extends Controller {
  static values = { urlTemplate: String, formulas: Object, fullSource: String }
  static targets = ["diagram", "toggleButton", "panel"]

  connect() {
    const c = this.readThemeColors()

    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "loose",
      theme: "base",
      // Mermaid refuses to parse a diagram whose source exceeds maxTextSize (default
      // 50,000 chars) or maxEdges (default 500), showing "Maximum text size in diagram
      // exceeded" instead of the graph. Those defaults are a DoS guard for untrusted,
      // user-pasted diagram text; this source is generated server-side by
      // FundFormulaDependencyGraph#to_mermaid from the fund's own formulas, so the only
      // thing they do here is break large funds. Each node's label is a full Bootstrap
      // stat-card of HTML (~800 chars), so a fund hits the 50k ceiling at roughly 60
      // formulas -- well within normal. Raised high enough that the fund's formula count,
      // not Mermaid's guard, is the limit.
      maxTextSize: 5_000_000,
      maxEdges: 5_000,
      themeVariables: {
        fontFamily: "Trebuchet MS, Verdana, Arial, sans-serif",
        // These must all stay real, parseable colors. With theme "base" Mermaid derives
        // further colors from these via its color library, and an unparseable value
        // ("transparent", undefined) makes that derivation produce invalid output --
        // which silently drops the edge lines while still drawing their arrowheads.
        // Mermaid's own node shape is hidden in CSS instead (see the stylesheet), since
        // each node's real visual is the Bootstrap card in its HTML label.
        primaryColor: c.bodyBg,
        primaryBorderColor: c.borderColor,
        secondaryColor: c.bodyBg,
        tertiaryColor: c.bodyBg,
        lineColor: c.lineColor,
      },
      // rankSpacing is the gap *on top of* the edge label, not a budget the label has to
      // fit inside: dagre lays each label out as its own virtual node between the ranks,
      // so the badge width is already accounted for and only the clearance either side
      // of it comes from here.
      // useMaxWidth:false keeps the SVG at its natural size. Left at the default, Mermaid
      // scales the whole diagram down to fit the container -- which on a fund with many
      // formulas shrinks every card and badge to an unreadable size. The container
      // scrolls horizontally instead (see the stylesheet).
      flowchart: {
        curve: "basis", padding: 8, nodeSpacing: 40, rankSpacing: 120,
        htmlLabels: true, useMaxWidth: false,
      },
    })

    // Captured before the first render, not lazily on toggle: mermaid.run() replaces the
    // element's content with the rendered SVG, so after it has run textContent is the
    // SVG's text rather than the diagram source.
    if (this.hasDiagramTarget) this.connectedSource = this.diagramTarget.textContent

    this.render()

    this.tooltip = document.createElement("div")
    this.tooltip.className = "fund-formula-graph-tooltip"
    document.body.append(this.tooltip)

    this.onMouseOver = this.handleMouseOver.bind(this)
    this.onMouseMove = this.handleMouseMove.bind(this)
    this.onMouseOut = this.handleMouseOut.bind(this)
    this.onClick = this.handleClick.bind(this)
    this.element.addEventListener("mouseover", this.onMouseOver)
    this.element.addEventListener("mousemove", this.onMouseMove)
    this.element.addEventListener("mouseout", this.onMouseOut)
    this.element.addEventListener("click", this.onClick)

    this.onBeforeCache = this.prepareForCache.bind(this)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)

    // On document rather than the panel: the panel is not focused when it opens, so a
    // listener on it would never see the key. Closing on Escape came for free with the
    // Bootstrap offcanvas this replaced.
    this.onKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  handleKeydown(event) {
    // Only when the panel is actually open, so this doesn't quietly swallow Escape from
    // anything else on the page.
    if (event.key !== "Escape") return
    if (!this.hasPanelTarget || !this.panelTarget.classList.contains("is-open")) return

    this.closePanel()
  }

  // Turbo snapshots the page as it stands and restores it on Back. The panel's open
  // state is just a class, so the snapshot round-trips it correctly either way; it is
  // closed here only so Back always lands on the diagram rather than a stale panel.
  prepareForCache() {
    this.closePanel()
    this.restoreDiagramSource()
  }

  // The rendered SVG survives in the snapshot as markup, but DOM event listeners do not
  // -- so the node click handlers Mermaid attached are gone on Back, and because the
  // element still carries data-processed Mermaid would skip re-rendering it, leaving
  // every node dead. Putting the source back means the restored page re-renders from
  // scratch in connect() and the nodes work again. Reset to the default (connected-only)
  // view so the cached diagram, the toggle flag and the button label all agree.
  restoreDiagramSource() {
    if (!this.hasDiagramTarget || !this.connectedSource) return

    this.diagramTarget.textContent = this.connectedSource
    this.diagramTarget.removeAttribute("data-processed")
    this.showingIsolated = false

    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.textContent = this.toggleButtonTarget.dataset.showLabel
    }
  }

  closePanel() {
    if (this.hasPanelTarget) this.panelTarget.classList.remove("is-open")
  }

  // run() rejects if Mermaid can't parse/render the diagram. Without a catch that
  // rejection is unhandled and the only trace is Mermaid's own error text swapped into
  // the page, so log the real reason -- the post-render fix-ups are skipped in that
  // case anyway.
  render() {
    return mermaid.run({ nodes: this.element.querySelectorAll(".mermaid") }).then(() => {
      this.reorderLayers()
      this.growSvgToFitCards()
    }).catch((error) => console.error("Fund formula dependency graph failed to render:", error))
  }

  // Swaps between the default diagram (formulas that depend on each other, plus any
  // with a broken reference) and the full one including the isolated formulas. The
  // default source is the one the server rendered, kept aside in connect() rather than
  // being sent a second time; the full one arrives as a value.
  toggleIsolated() {
    if (!this.hasDiagramTarget) return

    const diagram = this.diagramTarget
    this.showingIsolated = !this.showingIsolated

    diagram.textContent = this.showingIsolated ? this.fullSourceValue : this.connectedSource
    // Mermaid marks a rendered element and skips it on the next run() -- clear that so
    // the swapped-in source is actually drawn.
    diagram.removeAttribute("data-processed")

    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.textContent = this.showingIsolated
        ? "Hide unconnected formulas"
        : this.toggleButtonTarget.dataset.showLabel
    }

    this.render()
  }

  // Mermaid sizes the SVG from the label boxes it measured, but each node card renders
  // slightly wider/taller than that box (which is why the stylesheet lets the label
  // overflow) -- and an SVG clips anything past its viewBox, so the outermost cards came
  // out chopped. Measure what actually rendered and grow the SVG to cover it, widening
  // the viewBox by the same amount so the contents keep their 1:1 scale.
  growSvgToFitCards() {
    this.element.querySelectorAll("svg").forEach((svg) => {
      const svgBox = svg.getBoundingClientRect()
      let right = svgBox.right
      let bottom = svgBox.bottom

      svg.querySelectorAll(".node .card, .edgeLabels .badge").forEach((el) => {
        const box = el.getBoundingClientRect()
        right = Math.max(right, box.right)
        bottom = Math.max(bottom, box.bottom)
      })

      const extraX = Math.ceil(right - svgBox.right)
      const extraY = Math.ceil(bottom - svgBox.bottom)
      if (extraX <= 0 && extraY <= 0) return

      const growX = Math.max(extraX, 0)
      const growY = Math.max(extraY, 0)
      svg.setAttribute("width", Math.ceil(svgBox.width) + growX)
      svg.setAttribute("height", Math.ceil(svgBox.height) + growY)

      const viewBox = svg.getAttribute("viewBox")?.split(/[\s,]+/).map(Number)
      if (viewBox?.length === 4 && viewBox.every(Number.isFinite)) {
        svg.setAttribute("viewBox", `${viewBox[0]} ${viewBox[1]} ${viewBox[2] + growX} ${viewBox[3] + growY}`)
      }
    })
  }

  // SVG paints in document order and CSS z-index has no effect on SVG elements, so
  // layering is fixed by reordering the groups: arrows first (bottom), then the node
  // cards, then the field-name badges last (top). Left as Mermaid emits it, the arrows
  // strike through the badge text and the cards cover any badge that overlaps them.
  // Each group is moved within its own parent, so their transforms still apply.
  reorderLayers() {
    this.element.querySelectorAll("svg").forEach((svg) => {
      svg.querySelectorAll("g.edgePaths").forEach((group) => group.parentNode.prepend(group))
      svg.querySelectorAll("g.edgeLabels").forEach((group) => group.parentNode.append(group))
    })
  }

  // Reads the app's own Bootstrap theme tokens (Modernize template's --bs-* custom
  // properties) rather than hardcoding a palette, so the diagram automatically follows
  // whichever theme -- light or dark -- the app is actually rendering in right now.
  readThemeColors() {
    const styles = getComputedStyle(document.documentElement)
    const cssVar = (name, fallback) => styles.getPropertyValue(name).trim() || fallback

    return {
      bodyBg: cssVar("--bs-body-bg", "#fff"),
      borderColor: cssVar("--bs-border-color", "#ebf1f6"),
      // Edges use the body text color, not --bs-border-color: the border token is
      // nearly white in the light theme and the arrows disappeared against the canvas.
      lineColor: cssVar("--bs-body-color", "#5a6a85"),
    }
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("pageshow", this.onPageShow)
    this.element.removeEventListener("click", this.onClick)
    this.element.removeEventListener("mouseover", this.onMouseOver)
    this.element.removeEventListener("mousemove", this.onMouseMove)
    this.element.removeEventListener("mouseout", this.onMouseOut)
    this.tooltip?.remove()
  }

  showFormula(id) {
    const frame = document.getElementById("fund_formula_detail_frame")
    if (frame) frame.src = this.urlTemplateValue.replace("ID_PLACEHOLDER", id)

    if (this.hasPanelTarget) this.panelTarget.classList.add("is-open")
  }

  // Mermaid ids a node's wrapping <g> something like "flowchart-f51-3" -- the exact
  // scheme isn't part of Mermaid's public contract, so rather than hardcode it we
  // just pull the "f<id>" token out of whatever id string is actually there.
  formulaIdFor(nodeEl) {
    const source = nodeEl.dataset?.id || nodeEl.id || ""
    const match = source.match(/f(\d+)/)
    return match ? match[1] : null
  }

  // Clicks are handled by delegation rather than Mermaid's `click ... call` directive.
  // That directive can only invoke a function on `window`, which meant creating one in
  // connect() and deleting it in disconnect() -- and on a Turbo restore the outgoing
  // instance's disconnect() can run after the incoming one's connect(), deleting the
  // function the live controller had just installed and leaving every node dead. A
  // delegated listener has no such lifecycle coupling, and keeps working across
  // re-renders of the diagram.
  //
  // Also serves the broken-reference links above the diagram, which carry
  // data-formula-id rather than an inline onclick for the same reason.
  handleClick(event) {
    const link = event.target.closest("[data-formula-id]")
    if (link) {
      event.preventDefault()
      this.showFormula(link.dataset.formulaId)
      return
    }

    const nodeEl = event.target.closest(".node")
    if (!nodeEl) return

    const formulaId = this.formulaIdFor(nodeEl)
    if (formulaId) this.showFormula(formulaId)
  }

  handleMouseOver(event) {
    const nodeEl = event.target.closest(".node")
    if (!nodeEl || !this.element.contains(nodeEl)) return

    const formulaId = this.formulaIdFor(nodeEl)
    const text = formulaId && this.formulasValue[formulaId]
    if (!text) return

    this.tooltip.textContent = text
    this.tooltip.classList.add("is-visible")
  }

  handleMouseMove(event) {
    if (!this.tooltip.classList.contains("is-visible")) return

    this.tooltip.style.left = `${event.clientX + 16}px`
    this.tooltip.style.top = `${event.clientY + 16}px`
  }

  handleMouseOut(event) {
    const nodeEl = event.target.closest(".node")
    if (!nodeEl) return
    if (event.relatedTarget && nodeEl.contains(event.relatedTarget)) return

    this.tooltip.classList.remove("is-visible")
  }
}
