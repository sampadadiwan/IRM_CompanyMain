import { Controller } from "@hotwired/stimulus"

// Lets clients insert safe {{placeholder}} tokens into a CustomNotification's Trix body without
// knowing the available names - the list is keyed by email_method since different notification
// types are rendered by different mailers, each exposing a different set of placeholders.
export default class extends Controller {
    static values = { placeholders: Object }
    static targets = ["emailMethodSelect", "placeholderSelect", "editor"]

    connect() {
        this.renderOptions()
    }

    emailMethodChanged() {
        this.renderOptions()
    }

    renderOptions() {
        const emailMethod = this.emailMethodSelectTarget.value
        const names = this.placeholdersValue[emailMethod] || []

        this.placeholderSelectTarget.innerHTML = ""
        this.placeholderSelectTarget.append(new Option("+ Insert placeholder...", ""))
        names.forEach((name) => {
            this.placeholderSelectTarget.append(new Option(this.humanize(name), name))
        })
    }

    insert() {
        const name = this.placeholderSelectTarget.value
        if (!name) return

        // Trix keeps its own document model, so the token must go through editor.insertString
        // rather than touching the DOM/hidden input directly, or Trix will overwrite it on next input.
        this.editorTarget.editor.insertString(`{{${name}}}`)
        this.editorTarget.focus()
        this.placeholderSelectTarget.value = ""
    }

    humanize(name) {
        return name.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase())
    }
}
