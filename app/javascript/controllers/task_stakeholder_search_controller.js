import { Controller } from "@hotwired/stimulus"

// Stakeholder typeahead for the tasks filter bar (tasks/_filter_bar.html.erb).
//
// It replaces a <select> that carried one <option> per investor in the tenant.
// That was fine on the kanban board, which is opened deliberately, but the bar
// is now on the firm-wide tasks list and the dashboard "My Tasks" widget too —
// pages a large fund loads constantly, where inlining thousands of options costs
// a query with no LIMIT and a control nobody can scroll.
//
// jQuery UI autocomplete, matching investorsearch_controller.js: jquery-ui and
// its stylesheet are loaded by the layout, so this adds no dependency. The
// source is InvestorsController#search as JSON, which is capped per keystroke
// and scoped to the current tenant.
//
// The visible input has no name attribute and is never submitted. The hidden
// investor_id beside it is the filter TaskList actually reads.
export default class extends Controller {
  static targets = ["name", "id"]
  static values = { url: String }

  connect() {
    $(this.nameTarget).autocomplete({
      source: this.urlValue,
      // 2, not investorsearch_controller's 3: stakeholder names here are often
      // short and the caller already knows who they are looking for.
      minLength: 2,
      select: (event, ui) => {
        this.nameTarget.value = ui.item.label
        this.idTarget.value = ui.item.value
        this.submit()
        // false, so jQuery UI does not then write ui.item.value (the id) into
        // the visible box over the name we just put there.
        return false
      }
    })
  }

  disconnect() {
    // The frame this lives in is replaced wholesale on every filter change, so
    // without this each refresh would leave a detached menu behind.
    const $input = $(this.nameTarget)
    if ($input.data("uiAutocomplete")) $input.autocomplete("destroy")
  }

  // Emptying the box clears the filter. Without this the only way back to "All
  // Stakeholders" would be to reload the page, since the hidden field would keep
  // the last id whatever the box says.
  clear() {
    if (this.nameTarget.value.trim() !== "") return
    if (this.idTarget.value === "") return

    this.idTarget.value = ""
    this.submit()
  }

  submit() {
    this.element.closest("form")?.requestSubmit()
  }
}
