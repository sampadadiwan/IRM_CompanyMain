import { Controller } from "@hotwired/stimulus"

// Document form "New folder" popup: creates a folder inside the one picked in the Folder select,
// via folders#create as JSON (same action, policy and validation as the full New Folder page),
// then adds it to the select and picks it - without leaving the half-filled document form.
export default class extends Controller {
  static targets = ["name", "parent", "error"]
  static values = { url: String, select: String }

  connect() {
    // The popup is rendered inside the form card, which makes its own stacking context, so Bootstrap's
    // backdrop (appended to <body>) covered it and nothing in it could be clicked. Move it to <body>,
    // beside the backdrop. Moving it disconnects and reconnects this controller, so the listeners
    // below are set up on that second connect.
    if (this.element.parentElement !== document.body) {
      document.body.appendChild(this.element)
      return
    }

    // Each time the popup opens: say which folder it will go in, clear the last attempt
    this.onShow = () => {
      const select = this.select()
      const picked = select?.options[select.selectedIndex]
      this.parentTarget.textContent = picked ? picked.text : ""
      this.nameTarget.value = ""
      this.hideError()
    }
    // Focus the name box once the popup is visible
    this.onShown = () => this.nameTarget.focus()
    this.element.addEventListener("show.bs.modal", this.onShow)
    this.element.addEventListener("shown.bs.modal", this.onShown)
  }

  disconnect() {
    // Nothing to remove on the first disconnect (the move to <body>)
    if (!this.onShow) return
    this.element.removeEventListener("show.bs.modal", this.onShow)
    this.element.removeEventListener("shown.bs.modal", this.onShown)
  }

  select() {
    return document.querySelector(this.selectValue)
  }

  async create(event) {
    event?.preventDefault()
    const name = this.nameTarget.value.trim()
    if (!name) return this.showError("Enter a name for the folder.")

    const select = this.select()
    let response
    try {
      response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        // entity_id is set by the controller from the parent; parent_id is the folder picked in the form
        body: JSON.stringify({ folder: { name: name, parent_id: select?.value } })
      })
    } catch (_e) {
      return this.showError("Could not reach the server. Check your connection and try again.")
    }

    // 422: the folder's own validation messages, e.g. {"name": ["has already been taken"]}
    if (response.status === 422) {
      const errors = await response.json().catch(() => ({}))
      const messages = Object.entries(errors).flatMap(([field, msgs]) =>
        [].concat(msgs).map((m) => `${field.replace(/_/g, " ")} ${m}`))
      return this.showError(messages.join(". ") || "The folder could not be saved.")
    }
    // A refusal (deny_access) redirects to an HTML page, which fetch follows and reports as 200 - so
    // only a JSON answer counts as created
    const isJson = (response.headers.get("content-type") || "").includes("json")
    if (!response.ok || !isJson) {
      return this.showError(`The folder could not be created (error ${response.status}). You may not be allowed to add folders here.`)
    }

    // Created: add it to the select and pick it (select2 listens for "change")
    const folder = await response.json()
    if (select) {
      select.add(new Option(folder.full_path, folder.id, true, true))
      if (window.$) window.$(select).trigger("change")
    }
    window.bootstrap?.Modal.getOrCreateInstance(this.element).hide()
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("d-none")
  }

  hideError() {
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("d-none")
  }
}
