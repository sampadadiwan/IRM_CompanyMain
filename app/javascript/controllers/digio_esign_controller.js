/**
 * Embedded eSigning: hosts Digio's signing panel (SDK v11) on the signing page.
 * (openspec/changes/embedded-esign-digio, design card ③)
 *
 * The page hands this controller only the Digio document id and the signer's own email: Digio verifies
 * the signer itself, so there is no token. What the panel reports is a hint, never a status; the server
 * confirms with Digio.
 *
 * Usage (rendered by e_signatures/sign.html.erb):
 *   <div data-controller="digio-esign" data-digio-esign-provider-doc-id-value="DID..." ...>
 *     <p data-digio-esign-target="message" hidden></p>
 *     <button data-digio-esign-target="start" data-action="click->digio-esign#start">Start signing</button>
 *     <button data-digio-esign-target="retry" data-action="click->digio-esign#start" hidden>Try again</button>
 *   </div>
 */
import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["start", "retry", "message"]
  static values = {
    providerDocId: String,
    signerEmail: String,
    sdkUrl: String,
    environment: String,
    resultUrl: String,
    fallbackMessage: String,
    panelUnavailableMessage: String,
    cancelledMessage: String,
    completedMessage: String
  }

  connect() {
    this.finished = false
    // Load the SDK now, not on click: init() must be called synchronously from the click handler
    this.loadSdk()
  }

  disconnect() {
    this.cancelPanel()
  }

  /** Inject Digio's script once per page load. */
  loadSdk() {
    if (typeof window.Digio === "function") return
    if (document.querySelector("script[data-digio-sdk]")) return

    const script = document.createElement("script")
    script.src = this.sdkUrlValue
    script.async = true
    script.dataset.digioSdk = "true"
    // A failed load must not block a later attempt
    script.addEventListener("error", () => script.remove())
    document.head.appendChild(script)
  }

  /** Start signing (also used by Try again). Runs inside the user's click. */
  start(event) {
    event.preventDefault()

    if (typeof window.Digio !== "function") {
      this.loadSdk()
      this.report({ event: "client.panel_unavailable" })
      return
    }

    this.finished = false
    this.clearMessage()
    this.startTarget.hidden = true
    this.retryTarget.hidden = true

    const options = {
      environment: this.environmentValue,
      is_iframe: true,
      callback: (response) => this.onCallback(response),
      event_listener: (digioEvent) => this.onEvent(digioEvent)
    }

    // init() opens the panel and has to be called synchronously from the click
    this.digio = new window.Digio(options)
    this.digio.init()
    this.digio.submit(this.providerDocIdValue, this.signerEmailValue)
  }

  /**
   * The SDK's callback: success carries txn_id, a failure carries error_code. Closing the panel with X, before
   * or after the code is sent, arrives as error_code "CANCELLED" (seen in the Digio sandbox), not as an error.
   */
  onCallback(response) {
    const txnId = response && response.txn_id
    if (response && response.error_code === "CANCELLED") {
      this.report({ event: "client.cancelled" })
    } else if (response && response.error_code) {
      this.report({ event: "sign.failed", errorCode: response.error_code, txnId })
    } else if (response && (response.txn_id || response.digio_doc_id)) {
      this.report({ event: "sign.completed", txnId })
    } else {
      // The panel was closed without finishing
      this.report({ event: "client.cancelled" })
    }
  }

  /** The SDK's event stream: sign.<method>.completed | sign.<method>.failed carry the detail. */
  onEvent(digioEvent) {
    const name = String((digioEvent && digioEvent.event) || "")
    const txnId = digioEvent && digioEvent.txnId
    if (/^sign\.[a-z]+\.completed$/.test(name)) {
      this.report({ event: name, txnId })
    } else if (/^sign\.[a-z]+\.failed$/.test(name)) {
      const error = digioEvent.payload && digioEvent.payload.error
      this.report({ event: name, errorCode: error && error.code, txnId })
    }
  }

  /**
   * One outcome per attempt, whichever of callback and event_listener reports it first. The server maps it to a
   * message and an action; if the request fails the page falls back to what the outcome already tells us.
   * @param {{event: string, errorCode?: string, txnId?: string}} outcome
   */
  async report(outcome) {
    if (this.finished) return
    this.finished = true

    try {
      const response = await post(this.resultUrlValue, {
        body: JSON.stringify({ event: outcome.event, error_code: outcome.errorCode, txn_id: outcome.txnId }),
        contentType: "application/json",
        responseKind: "json"
      })
      const data = await response.json
      if (data && data.message) {
        this.showMessage(data.message, { retry: data.action === "retry", start: outcome.event === "client.cancelled" })
        return
      }
    } catch (_error) { /* use the local fallback below */ }

    this.showLocalOutcome(outcome)
  }

  /** What the page can say without the server, e.g. when the request could not be made. */
  showLocalOutcome(outcome) {
    if (/completed$/.test(outcome.event)) {
      // The signer finished in the panel; the confirmation arrives from Digio either way
      this.showMessage(this.completedMessageValue, { retry: false })
    } else if (outcome.event === "client.cancelled") {
      this.showMessage(this.cancelledMessageValue, { retry: false, start: true })
    } else if (outcome.event === "client.panel_unavailable") {
      this.showMessage(this.panelUnavailableMessageValue, { retry: true })
    } else {
      this.showMessage(this.fallbackMessageValue, { retry: true })
    }
  }

  /** start: offer "Start signing" again (the panel was closed); retry: offer "Try again" (an error to fix). */
  showMessage(text, { retry, start = false }) {
    this.messageTarget.textContent = text
    this.messageTarget.hidden = false
    this.startTarget.hidden = !start
    this.retryTarget.hidden = !retry || start
  }

  clearMessage() {
    this.messageTarget.textContent = ""
    this.messageTarget.hidden = true
  }

  /** Close the panel if the page is left while it is open. */
  cancelPanel() {
    if (this.digio && typeof this.digio.cancel === "function") {
      try { this.digio.cancel() } catch (_error) { /* the panel is already gone */ }
    }
    this.digio = null
  }
}
