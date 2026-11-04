import { Controller } from "@hotwired/stimulus"
import { initSelect2 } from "custom/select2_handler"

export default class extends Controller {
  static targets = ["container", "metadataInput", "field"]

  connect() {
    this.syncFromMetadata()
    // Initial update to ensure hidden field is populated if fields exist
    this.debounceUpdate()
  }

  fieldTargetConnected(field) {
    this.syncFieldFromMetadata(field)
    if (field.multiple) this.connectMultiple(field)
    this.debounceUpdate()
  }

  // Multi-selects (stats Fields) are select2 widgets. E18 — fields inserted by the metadata_help turbo stream miss
  // the turbo:load / turbo:frame-load hooks, so initialise here. select2 fires jQuery change events, which a
  // data-action never hears, so listen through jQuery.
  connectMultiple(field) {
    if (!field.classList.contains("select2-hidden-accessible")) initSelect2(field.parentElement)
    $(field).off("change.metadataForm").on("change.metadataForm", () => this.debounceUpdate())
  }

  debounceUpdate() {
    if (this.updateTimer) clearTimeout(this.updateTimer)
    this.updateTimer = setTimeout(() => {
      this.updateMetadata()
    }, 100)
  }

  // Triggered when any dynamic field changes
  updateMetadata() {
    const fields = this.fieldTargets
    if (fields.length === 0) return

    const metadata = {}

    fields.forEach(field => {
      const key = field.dataset.metadataKey
      let value

      if (field.multiple) {
        // H1 — selected options are in DOM order, which select2_handler keeps in pick order. E17 — none picked
        // leaves the key out.
        const picked = Array.from(field.selectedOptions).map(option => option.value)
        if (picked.length === 0) return
        value = picked.join(", ")
      } else if (field.tagName === "SELECT") {
        if (field.value === "") return // Skip "Default"
        value = field.value === "true" ? true : (field.value === "false" ? false : field.value)
      } else if (field.type === "number") {
        if (field.value === "") return // Skip empty
        value = field.dataset.metadataInteger ? parseInt(field.value, 10) : parseFloat(field.value)
      } else if (field.dataset.metadataType === "array") {
        if (field.value === "") return // Skip empty
        value = field.value.split(",").map(s => s.trim()).filter(s => s !== "")
      } else {
        if (field.value === "") return // Skip empty
        value = field.value
      }
      metadata[key] = value
    })

    const rubyHash = this.toRubyHash(metadata)
    this.metadataInputTarget.value = rubyHash === "{}" ? "" : rubyHash
  }

  // Whole-number settings (IDs): refuse the characters a number input still lets through (e + - . ,) and keep only
  // digits when text is pasted. E9, E10, E11
  guardInteger(event) {
    const field = event.target
    if (event.type === "keydown") {
      if (["e", "E", "+", "-", ".", ","].includes(event.key)) event.preventDefault()
    } else if (event.type === "paste") {
      event.preventDefault()
      field.value = (event.clipboardData || window.clipboardData).getData("text").replace(/\D/g, "")
      field.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  // Very basic JSON to Ruby Hash converter
  toRubyHash(obj) {
    const entries = Object.entries(obj)
    if (entries.length === 0) return "{}"

    const parts = entries.map(([key, value]) => {
      let valStr
      if (typeof value === "string") {
        valStr = `'${value.replace(/'/g, "\\'")}'`
      } else if (Array.isArray(value)) {
        valStr = "[" + value.map(v => `'${v.replace(/'/g, "\\'")}'`).join(", ") + "]"
      } else {
        valStr = value
      }
      return `${key}: ${valStr}`
    })
    return `{${parts.join(", ")}}`
  }

  // Parse current metadata and fill dynamic fields
  syncFromMetadata() {
    this.fieldTargets.forEach(field => this.syncFieldFromMetadata(field))
  }

  syncFieldFromMetadata(field) {
    const raw = this.metadataInputTarget.value
    if (!raw || raw === "{}") return

    const key = field.dataset.metadataKey
    const values = this.parseRubyHash(raw)

    if (field.multiple) {
      if (values[key] !== undefined) this.restoreMultiple(field, values[key])
      return
    }

    if (values[key] !== undefined) {
      field.value = values[key].toString()
    }
  }

  // H2 — select the saved names (any case) and move them to the front in saved order, so the chips read in that order
  restoreMultiple(field, saved) {
    const names = String(saved).split(",").map(name => name.trim().toLowerCase()).filter(name => name !== "")
    const options = Array.from(field.options)
    const picked = [...new Set(names.map(name => options.find(option => option.value.toLowerCase() === name)).filter(Boolean))]

    options.forEach(option => { option.selected = picked.includes(option) })
    picked.slice().reverse().forEach(option => field.prepend(option))
    if ($(field).data("select2")) $(field).trigger("change.select2")
  }

  parseRubyHash(raw) {
    const regex = /(?:(\w+)|["']([^"']+)["'])\s*:\s*(\[[^\]]*\]|'[^']*'|"[^"]*"|[^,{}]+)/g
    let match
    const values = {}

    while ((match = regex.exec(raw)) !== null) {
      const key = match[1] || match[2]
      let val = match[3].trim()

      if ((val.startsWith("'") && val.endsWith("'")) || (val.startsWith('"') && val.endsWith('"'))) {
        val = val.substring(1, val.length - 1)
      } else if (val.startsWith("[") && val.endsWith("]")) {
        val = val.substring(1, val.length - 1)
                 .split(",")
                 .map(s => s.trim().replace(/^['"]|['"]$/g, ""))
                 .join(", ")
      } else if (val === "true") {
        val = true
      } else if (val === "false") {
        val = false
      } else if (!isNaN(val) && val !== "") {
        val = parseFloat(val)
      }
      
      values[key] = val
    }
    return values
  }
}
