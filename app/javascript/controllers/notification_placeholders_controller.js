import { Controller } from "@hotwired/stimulus"

// Lets clients insert safe {{placeholder}} tokens into a CustomNotification's Trix body without
// knowing the available names - the list is keyed by email_method since different notification
// types are rendered by different mailers, each exposing a different set of placeholders.
export default class extends Controller {
    static values = { placeholders: Object, fundDefaults: Object, autoAttachMethods: Array }
    static targets = ["emailMethodSelect", "placeholderSelect", "editor", "overrideWarning", "blankAttachmentHint"]

    connect() {
        this.renderOptions()
        this.renderOverrideWarning()
        this.renderBlankAttachmentHint()
    }

    emailMethodChanged() {
        this.renderOptions()
        this.renderOverrideWarning()
        this.renderBlankAttachmentHint()
    }

    // Some mailers (e.g. CapitalRemittanceMailer#notify_capital_remittance/reminder_capital_remittance,
    // CapitalDistributionPaymentsMailer#send_notification) always attach the owner's own generated
    // notice document via attach_all_files, regardless of attachment_names - so "blank" doesn't mean
    // "no attachments" for those. See CustomNotification::AUTO_ATTACHED_EMAIL_METHODS.
    renderBlankAttachmentHint() {
        if (!this.hasBlankAttachmentHintTarget) return

        const emailMethod = this.emailMethodSelectTarget.value
        const autoAttaches = this.autoAttachMethodsValue.includes(emailMethod)

        this.blankAttachmentHintTarget.textContent = autoAttaches
            ? "this email's own generated notice document is still attached automatically - this field only adds extra documents on top of it."
            : "this email is sent with no attachments."
    }

    // Warns that saving this call/distribution-specific notification will override the fund's
    // default for the currently selected email, since the fund-level one is only a fallback.
    renderOverrideWarning() {
        if (!this.hasOverrideWarningTarget) return

        const emailMethod = this.emailMethodSelectTarget.value
        const subject = this.fundDefaultsValue[emailMethod]

        if (subject) {
            this.overrideWarningTarget.textContent = `Heads up: this fund already has a default notification for this email ("${subject}"). Saving this will override that default for this specific record.`
            this.overrideWarningTarget.classList.remove("d-none")
        } else {
            this.overrideWarningTarget.classList.add("d-none")
        }
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
