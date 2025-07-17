import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  static targets = ["kycSelect", "employeeSelect", "esignEmailsField"]
  static values = {
    kycUrl: String,
    employeeUrl: String,
    param: String,
    esignUrl: String
  }

  connect() {
    // Initialize select2 for all .select2 elements, including investor and kyc selects
    $(".select2").on('select2:select', function () {
      let event = new Event('change', { bubbles: true }) // fire a native event
      this.dispatchEvent(event);
    });

    // Re-initialize select2 on kycSelectTarget when the controller connects (after Turbo Stream update)
    $(this.kycSelectTarget).select2();

    // If a value is pre-selected in the kycSelectTarget, fetch esign emails
    if (this.kycSelectTarget.value) {
      this._fetchEsignEmails();
    }

    // Direct listener for kycSelectTarget's native change event (for programmatic changes from Turbo Stream)
    this.kycSelectTarget.addEventListener("change", () => {
      this._fetchEsignEmails();
    });

    // Direct listener for kycSelectTarget's select2:select event (for manual user selection)
    $(this.kycSelectTarget).on('select2:select', () => {
      this._fetchEsignEmails();
    });
  }

  change(event) {
    console.log(this.kycUrlValue);
    console.log(this.employeeUrlValue);

    let params = new URLSearchParams()
    params.append(this.paramValue, event.target.selectedOptions[0].value)
    params.append("target", this.kycSelectTarget.id)

    get(`${this.kycUrlValue}?${params}`, {
      responseKind: "turbo-stream"
    });

    let params2 = new URLSearchParams()
    params2.append(this.paramValue, event.target.selectedOptions[0].value)
    params2.append("target", this.employeeSelectTarget.id)

    get(`${this.employeeUrlValue}?${params2}`, {
      responseKind: "turbo-stream"
    });
  }

  kycChange(event) {
    this._fetchEsignEmails();
  }

  _fetchEsignEmails() {
    const selectedKycId = this.kycSelectTarget.value;
    if (selectedKycId) {
      const params = new URLSearchParams();
      params.append("investor_kyc_id", selectedKycId);

      get(`${this.esignUrlValue}?${params}`, {
        responseKind: "json"
      }).then(response => {
        if (response.ok) {
          response.json.then(data => {
            this.esignEmailsFieldTarget.value = data.esign_emails || "";
          });
        } else {
          console.error("Failed to fetch esign emails:", response.statusText);
          this.esignEmailsFieldTarget.value = "";
        }
      });
    } else {
      this.esignEmailsFieldTarget.value = "";
    }
  }
}