import { Controller } from "@hotwired/stimulus"

// Calls the suggest_sections endpoint and injects new section fields into the nested form.
// Usage: data-controller="suggest-sections"
//        data-suggest-sections-url-value="<suggest_sections_url>"
//        data-suggest-sections-container-value="#sections"
export default class extends Controller {
  static values = { url: String }

  suggest(event) {
    event.preventDefault()
    const btn = event.currentTarget
    btn.disabled = true
    btn.innerHTML = `<span class="spinner-border spinner-border-sm me-1"></span>Asking AI…`

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Accept":       "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      }
    })
      .then(r => r.json())
      .then(({ sections, error }) => {
        if (error) {
          alert("AI suggestion failed: " + error)
          return
        }
        // Cocoon adds nested fields via the "Add Section" link — we simulate clicking it
        // then populate the newly added fields.
        sections.forEach(sec => {
          // Click the Cocoon add-association link to insert blank fields
          const addLink = document.querySelector("a[data-association='portfolio_report_section']")
          if (addLink) addLink.click()

          // Find the last set of nested fields and fill them in
          const allNested = document.querySelectorAll(".nested-fields")
          const last      = allNested[allNested.length - 1]
          if (!last) return

          const nameInput         = last.querySelector("input[name*='[name]']")
          const dataTextarea      = last.querySelector("textarea[name*='[data]']")
          const iconInput         = last.querySelector("input[name*='[icon]']")

          if (nameInput)    nameInput.value    = sec.name        || ""
          if (dataTextarea) dataTextarea.value = sec.instructions || ""
          if (iconInput)    iconInput.value    = sec.icon         || ""
        })
      })
      .catch(err => alert("Request failed: " + err))
      .finally(() => {
        btn.disabled = false
        btn.innerHTML = `<i class="ti ti-wand me-1"></i>Suggest Sections (AI)`
      })
  }
}
