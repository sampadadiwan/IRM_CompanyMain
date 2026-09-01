import { Controller } from "@hotwired/stimulus"

// Live read-only recap shown on the wizard's final "Review & Save" step. Reads the
// other fields in the same form rather than duplicating their values, so it can
// never drift out of sync with what will actually be saved.
export default class extends Controller {
  static targets = [
    "emailMethod", "to", "tag", "subject", "body", "whatsapp",
    "attachmentNames", "enabled", "enabledBanner", "enabledIcon",
    "showDetails", "showDetailsLink"
  ]

  connect() {
    this.refresh()
  }

  refresh() {
    this.emailMethodTarget.textContent = this.selectText("custom_notification_email_method") || "(not selected)"

    if (this.hasToTarget) {
      this.toTarget.textContent = this.selectText("custom_notification_to") || "Default recipients for this notification type"
    }

    this.setValue(this.tagTarget, this.fieldValue("custom_notification_tag"), "—")
    this.setValue(this.subjectTarget, this.fieldValue("custom_notification_subject"), "(no subject set)")

    const body = this.bodyPreview()
    this.setValue(this.bodyTarget, body.empty ? "" : body.text, "(empty — no email will be sent)")

    this.setValue(this.whatsappTarget, this.fieldValue("custom_notification_whatsapp"), "(none — no WhatsApp message will be sent)")
    this.setValue(this.attachmentNamesTarget, this.fieldValue("custom_notification_attachment_names"), "(none — no attachments will be sent)")

    const enabled = this.fieldChecked("custom_notification_enabled")
    this.enabledTarget.textContent = enabled
      ? "This template is active and will be used for this notification."
      : "This template is saved but inactive — the default email will keep being used instead."
    this.enabledBannerTarget.classList.toggle("alert-success", enabled)
    this.enabledBannerTarget.classList.toggle("alert-warning", !enabled)
    this.enabledIconTarget.classList.toggle("ti-circle-check", enabled)
    this.enabledIconTarget.classList.toggle("ti-alert-triangle", !enabled)

    if (this.hasShowDetailsTarget) {
      this.setToggleSentence(
        this.showDetailsTarget,
        this.fieldChecked("custom_notification_show_details"),
        "Included",
        "Not included"
      )
    }

    this.setToggleSentence(
      this.showDetailsLinkTarget,
      this.fieldChecked("custom_notification_show_details_link"),
      "Included",
      "Not included"
    )
  }

  // Renders a checkbox's effect as a plain-language sentence instead of a bare
  // Yes/No, and mutes the "nothing happens" case so it reads as the quieter option.
  setToggleSentence(target, isOn, onText, offText) {
    target.textContent = isOn ? onText : offText
    target.classList.toggle("text-muted", !isOn)
  }

  // Renders a real value normally, or a muted/italic placeholder when the field is
  // empty, so an at-a-glance scan of the review step can tell "set" from "not set".
  setValue(target, value, placeholder) {
    target.textContent = value || placeholder
    target.classList.toggle("text-muted", !value)
    target.classList.toggle("fst-italic", !value)
  }

  bodyPreview() {
    const editor = document.querySelector('[data-notification-placeholders-target="editor"]')
    if (!editor) return { text: "", empty: true }

    // .innerText depends on the element actually being laid out/rendered, which it
    // isn't while step-3 is hidden behind this step (always the case here, since this
    // is the last step) — it silently returns "". .innerHTML has no such dependency;
    // turn its block breaks into newlines ourselves before stripping the markup.
    const container = document.createElement("div")
    container.innerHTML = editor.innerHTML.replace(/<\/(div|p)>/gi, "\n").replace(/<br\s*\/?>/gi, "\n")
    const text = container.textContent.trim()

    if (!text) return { text: "", empty: true }
    return { text, empty: false }
  }

  fieldValue(id) {
    const el = document.getElementById(id)
    return el ? el.value : ""
  }

  fieldChecked(id) {
    const el = document.getElementById(id)
    return el ? el.checked : false
  }

  selectText(id) {
    const el = document.getElementById(id)
    if (!el || el.selectedIndex < 0) return ""
    const option = el.options[el.selectedIndex]
    return option ? option.text : ""
  }
}
