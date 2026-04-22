import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "metadataInput", "field"]

  connect() {
    this.syncFromMetadata()
    // Initial update to ensure hidden field is populated if fields exist
    this.debounceUpdate()
  }

  fieldTargetConnected(field) {
    this.syncFieldFromMetadata(field)
    this.debounceUpdate()
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

      if (field.tagName === "SELECT") {
        if (field.value === "") return // Skip "Default"
        value = field.value === "true" ? true : (field.value === "false" ? false : field.value)
      } else if (field.type === "number") {
        if (field.value === "") return // Skip empty
        value = parseFloat(field.value)
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

    if (values[key] !== undefined) {
      field.value = values[key].toString()
    }
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
