import { Controller } from "@hotwired/stimulus"

// Evergreen settings wizard helpers (the step bar itself is the shared `wizard` controller):
// - shows a field only when it applies (data-show-field / data-show-values, ">0" for "any positive number")
// - "Typical setup" select fills the fields from the preset's values (JSON; nothing is saved), so it
//   works on New Fund before the fund exists and keeps everything else that was typed
// - on New Fund and Edit Fund, builds one class card per unit type typed in the fund's Unit Types (syncClasses)
// - writes the plain-English Review summary and lets "Edit" jump back to a step
export default class extends Controller {
  static targets = ["conditional", "summary", "classes", "classTemplate", "noClasses", "pricesMissing"]
  // feeLabel: the locale's name for the soft lock-up fee (EvergreenLabels :early_fee), lower-cased for the summary
  static values = { presetUrl: String, currency: String, feeLabel: { type: String, default: "early redemption fee" } }

  connect() {
    // Required fields are checked before the wizard moves on (capture phase, so this runs before the
    // wizard's own Next/submit handler and can stop it)
    this.checkRequired = this.checkRequired.bind(this)
    this.element.addEventListener("click", this.checkRequired, true)
    this.refresh = this.refresh.bind(this)
    this.element.addEventListener("change", this.refresh)
    this.element.addEventListener("input", this.refresh)
    this.refresh()
  }

  // A step's required fields (data-eg-required, plus "at least one" groups) must be filled before Next
  // or Create fund; only fields showing on the current step count, so hidden conditional ones don't block
  checkRequired(event) {
    const button = event.target.closest(".nextBtn, button[type=submit]")
    if (!button) return
    const step = button.closest(".setup-content")
    if (!step || !step.querySelector("[data-eg-required], [data-eg-required-group]")) return
    let firstBad = null
    step.querySelectorAll("[data-eg-required]").forEach((input) => {
      const visible = input.offsetParent !== null
      const empty = visible && `${input.value}`.trim() === ""
      this.markRequired(input, empty)
      if (empty && !firstBad) firstBad = input
    })
    step.querySelectorAll("[data-eg-required-group]").forEach((group) => {
      const none = group.offsetParent !== null && !group.querySelector("input[type=checkbox]:checked")
      group.classList.toggle("text-danger", none)
      let note = group.querySelector(".eg-required-note")
      if (none && !note) {
        note = document.createElement("div")
        note.className = "form-text text-danger eg-required-note"
        note.textContent = "Choose at least one"
        group.appendChild(note)
      } else if (!none && note) note.remove()
      if (none && !firstBad) firstBad = group.querySelector("input")
    })
    if (!firstBad) return
    event.preventDefault()
    event.stopPropagation()
    firstBad.focus()
  }

  markRequired(input, bad) {
    input.classList.toggle("is-invalid", bad)
    const holder = input.closest(".input-group") || input
    let note = holder.parentElement.querySelector(":scope > .eg-required-note")
    if (bad && !note) {
      note = document.createElement("div")
      note.className = "form-text text-danger eg-required-note"
      note.textContent = "Required"
      holder.after(note)
    } else if (!bad && note) note.remove()
    if (bad && !input.dataset.egWatch) {
      // clears as soon as something is typed
      input.dataset.egWatch = "1"
      input.addEventListener("input", () => { if (`${input.value}`.trim() !== "") this.markRequired(input, false) })
    }
  }

  disconnect() {
    this.element.removeEventListener("click", this.checkRequired, true)
    this.element.removeEventListener("change", this.refresh)
    this.element.removeEventListener("input", this.refresh)
  }

  // evergreen-fund-on-create H1: fill from the preset in place (no reload, no fund needed)
  async applyPreset(event) {
    const name = event.target.value
    if (!name) return
    const response = await fetch(this.presetUrlValue.replace("__NAME__", encodeURIComponent(name)), { headers: { Accept: "application/json" } })
    if (!response.ok) return
    const values = await response.json()
    // Fields filled by the previous setup lose their "From preset" badge; this setup marks its own
    this.element.querySelectorAll(".preset-badge").forEach((b) => b.remove())
    Object.entries(values).forEach(([key, value]) => {
      if (key === "early_redemption_fee") {
        this.setField("early_fee_pct", value?.pct ?? "")
        this.setField("early_fee_schedule", "")
      } else {
        this.setField(key, value)
      }
    })
    this.setField("preset", name)
    // The chosen setup is marked in the "What each setup means" list
    this.element.querySelectorAll('[id^="preset_summary_"]').forEach((el) => {
      const chosen = el.id === `preset_summary_${name}`
      el.classList.toggle("border-info", chosen) // theme colour (info), like the rest of the evergreen screens
      const mark = el.querySelector(".preset-mark")
      if (mark) mark.textContent = chosen ? " ✓" : ""
    })
    this.refresh()
  }

  // evergreen-fund-on-create X2: on New Fund, Create fund first checks every class has a starting price;
  // if not, it goes to the Classes step, outlines the empty boxes and names the classes — nothing is sent
  checkStartingPrices(event) {
    const missing = []
    this.element.querySelectorAll('[id^="class_term_"]').forEach((card) => {
      const price = card.querySelector('input[name$="[initial_price]"]')
      const empty = !price || !(parseFloat(price.value) > 0)
      price?.classList.toggle("is-invalid", empty)
      if (empty) missing.push(`Class ${card.querySelector('input[name$="[unit_type]"]').value}`)
    })
    if (missing.length === 0) {
      if (this.hasPricesMissingTarget) this.pricesMissingTarget.classList.add("d-none")
      return
    }
    event.preventDefault()
    if (this.hasPricesMissingTarget) {
      this.pricesMissingTarget.textContent = `Enter a starting price for ${missing.join(", ")} — it prices the first subscriptions until the class has an approved NAV.`
      this.pricesMissingTarget.classList.remove("d-none")
    }
    const link = this.element.querySelector(`#wizard_step_${event.currentTarget.dataset.classesStep}`)
    if (link) { link.classList.remove("disabled"); link.click() }
  }

  setField(name, value) {
    const el = this.field(name)
    if (!el) return
    el.value = value ?? ""
    el.dispatchEvent(new Event("change", { bubbles: true }))
    // A field the preset set (not one it only cleared) gets a small note under it — under, not in the
    // label, so labels stay on one line and the boxes in a row stay aligned
    const group = el.closest(".form-group")
    if (group && name !== "preset" && `${value ?? ""}` !== "" && !group.querySelector(".preset-badge")) {
      const note = document.createElement("div")
      note.className = "form-text text-info preset-badge"
      note.innerHTML = '<i class="ti ti-wand me-1"></i>Filled from the preset'
      note.title = "Set by the setup you picked"
      group.appendChild(note)
    }
  }

  // evergreen-fund-on-create E2, E3: on New Fund the Classes step has one card per unit type typed in
  // step 1 (comma-separated, trimmed, duplicates dropped); a card keeps its values while its class stays
  syncClasses() {
    if (!this.hasClassTemplateTarget || !this.hasClassesTarget) return
    const input = this.element.querySelector("#fund_unit_types")
    if (!input) return
    const wanted = [...new Set(input.value.split(",").map((u) => u.trim()).filter(Boolean))]
    if (wanted.join("|") === this.syncedUnits) return
    this.syncedUnits = wanted.join("|")
    const existing = new Map([...this.classesTarget.querySelectorAll('[id^="class_term_"]')]
      .map((card) => [card.querySelector('input[name$="[unit_type]"]').value, card]))
    // A class already saved (Edit Fund) is never removed here — it may hold units; only unsaved cards go
    existing.forEach((card, unit) => {
      if (!wanted.includes(unit) && !card.querySelector('input[name$="[id]"]')) card.remove()
    })
    wanted.forEach((unit) => {
      let card = existing.get(unit)
      if (!card) {
        this.classIndex = (this.classIndex || 1000) + 1
        const slug = unit.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "")
        const html = this.classTemplateTarget.innerHTML
          .replaceAll("UNITTOKEN", unit).replaceAll("unittoken", slug).replaceAll("IDXTOKEN", this.classIndex)
        const holder = document.createElement("div")
        holder.innerHTML = html.trim()
        card = holder.firstElementChild
      }
      this.classesTarget.appendChild(card) // keeps the typed order
    })
    // No unit types yet: explain instead of showing an empty step
    if (this.hasNoClassesTarget) this.noClassesTarget.classList.toggle("d-none", wanted.length > 0)
  }

  // Edit links on the Review step jump to their step via the step bar
  goto(event) {
    event.preventDefault()
    const link = this.element.querySelector(`#wizard_step_${event.currentTarget.dataset.step}`)
    if (link) { link.classList.remove("disabled"); link.click() }
  }

  refresh() {
    this.syncClasses()
    this.conditionalTargets.forEach((el) => {
      const value = this.val(el.dataset.showField)
      const wanted = el.dataset.showValues
      const show = wanted === ">0" ? parseFloat(value || "0") > 0 : wanted.split(",").includes(value)
      el.classList.toggle("d-none", !show)
    })
    // Review cards: one list item per point (evergreen-fund-on-create review)
    this.summaryTargets.forEach((el) => {
      const items = this.summary(el.dataset.section)
      el.replaceChildren(...items.map((text) => {
        const li = document.createElement("li")
        li.className = "mb-1"
        li.textContent = text
        return li
      }))
    })
  }

  // ---- reading the form ----
  field(name) { return this.element.querySelector(`[name="evergreen_fund_setting[${name}]"]`) }

  val(name) {
    const el = this.field(name)
    return el ? el.value : ""
  }

  text(name) {
    const el = this.field(name)
    if (!el) return ""
    return el.tagName === "SELECT" ? (el.options[el.selectedIndex]?.text || "") : el.value
  }

  num(name) { return parseFloat(this.val(name) || "0") }

  money(name) {
    const n = this.num(name)
    return n > 0 ? `${this.currencyValue} ${n.toLocaleString()}` : null
  }

  // ---- Review points (one list item each) ----
  fundField(id) { return this.element.querySelector(`#${id}`) }

  summary(section) {
    switch (section) {
      case "fund": {
        const name = this.fundField("fund_name")?.value || "— no name yet —"
        const currency = this.fundField("fund_currency")?.value
        const units = (this.fundField("fund_unit_types")?.value || "").split(",").map((u) => u.trim()).filter(Boolean)
        return [`${name}`, "Open-ended (evergreen)", currency ? `Currency ${currency}` : null,
                units.length ? `Classes: ${[...new Set(units)].join(", ")}` : "No unit classes yet — add Unit Types on step 1"].filter(Boolean)
      }
      case "calendar": {
        const day = this.val("dealing_day") === "day_n" ? `day ${this.val("dealing_day_n")} of the month` : this.text("dealing_day").toLowerCase()
        return [`Subscriptions: ${this.text("subscription_calendar").toLowerCase()}`, `Redemptions: ${this.text("redemption_calendar").toLowerCase()}`,
                `Dealing on the ${day}`]
      }
      case "subscriptions": {
        const pay = this.val("payment_timing") === "after"
          ? `Investors pay within ${this.val("pay_after_days")} days after the dealing date`
          : `Investors pay before dealing, by the cut-off ${this.val("subscription_cutoff_days")} days before`
        return [pay,
                this.money("min_initial_subscription") ? `Minimum first subscription ${this.money("min_initial_subscription")}` : "No minimum first subscription",
                this.money("min_additional_subscription") ? `Minimum top-up ${this.money("min_additional_subscription")}` : "No minimum top-up",
                `Orders not ready in time are ${this.val("unready_handling") === "cancel" ? "cancelled" : "rolled to the next dealing date"}`]
      }
      case "redemptions": {
        const forms = [...this.element.querySelectorAll('input[name="evergreen_fund_setting[redemption_forms][]"][type=checkbox]:checked')]
          .map((c) => (this.element.querySelector(`label[for="${c.id}"]`) || c.closest("label"))?.textContent.trim().toLowerCase())
        const lock = this.num("lock_up_months") > 0
          ? (this.val("lock_up_type") === "soft"
            ? `${this.val("lock_up_months")}-month soft lock-up${this.num("early_fee_pct") > 0 ? ` (${this.val("early_fee_pct")}% ${this.feeLabelValue})` : ""}`
            : `${this.val("lock_up_months")}-month hard lock-up`)
          : "No lock-up"
        return [`Redeem by ${forms.length ? forms.join(", ") : "— choose at least one —"}`, `${this.val("notice_days")} days' notice`,
                `Paid within ${this.val("redemption_settlement_days")} business days`, lock,
                this.money("min_holding") ? `Minimum holding ${this.money("min_holding")}` : null].filter(Boolean)
      }
      case "gates": {
        const cap = this.num("investor_gate_pct") > 0 ? `Each investor at most ${this.val("investor_gate_pct")}% of their holding per period` : "No per-investor cap"
        if (this.num("gate_pct") <= 0) return ["No fund gate", cap]
        return [`At most ${this.val("gate_pct")}% of ${this.val("gate_level") === "class" ? "each class's" : "the fund's"} NAV per ${this.text("gate_period").replace(/^Each /, "").toLowerCase()}`,
                this.val("gate_method") === "fifo" ? "First received, first paid" : "Pro-rata across orders",
                "The rest is carried to the next dealing date", cap]
      }
      case "classes": {
        const rows = [...this.element.querySelectorAll('[id^="class_term_"]')].map((card) => {
          const cls = card.querySelector('input[name$="[unit_type]"]').value
          const price = card.querySelector('input[name$="[initial_price]"]').value
          const perf = card.querySelector('select[name$="[perf_fee_model]"]').value === "class_hwm"
            ? `, ${card.querySelector('input[name$="[perf_fee_pct]"]').value || 0}% performance fee` : ""
          const expenses = card.querySelector('input[name$="[class_expense_entry_name]"]')?.value
          const own = expenses ? `, own expenses "${expenses}"` : ""
          return `Class ${cls}: starting price ${price ? `${this.currencyValue} ${parseFloat(price).toLocaleString()}` : "— not set —"}${perf}${own}`
        })
        // What investors hold (unit_term): the firm's word (blank, "Firm's wording (Units)"), Units or Shares
        const chosen = this.text("unit_term")
        const word = (chosen.match(/\(([^)]+)\)/)?.[1] || chosen || "units").toLowerCase()
        const holds = `Investors hold ${word}`
        return [holds, ...(rows.length ? rows : ["No unit classes yet — add Unit Types on step 1"])]
      }
      case "notifications": {
        const on = [...this.element.querySelectorAll('input[type=checkbox][id^="notification_"]')].filter((c) => c.checked)
          .map((c) => c.closest("li").querySelector("span").firstChild.textContent.trim())
        return [on.length ? `On: ${on.join(", ")}` : "Only the everyday investor emails",
                `Reminders ${this.element.querySelector("#notification_reminder_days")?.value || 2} days before the cut-off`]
      }
      case "journeys":
        return [`Per-order journeys: ${this.text("order_journeys").toLowerCase()}`, `NAV cash from "${this.val("cash_entry_name")}"`,
                `Fees paid from "${this.val("mgmt_fee_paid_entry_name")}" and "${this.val("perf_fee_paid_entry_name")}"`]
      default:
        return []
    }
  }
}
