import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  static targets = ["kycSelect", "employeeSelect", "esignEmailsOutput"]

  static values = {
    kycUrl: String,
    employeeUrl: String,
    param: String,
    emailUrl: String,
    emailParam: String
  }

  connect() {
    $(".select2").on('select2:select', function () {
      let event = new Event('change', { bubbles: true }) // fire a native event
      this.dispatchEvent(event);
    });
  }

  change(event) {

    console.log(this.kycUrlValue);
    console.log(this.employeeUrlValue);

    let params = new URLSearchParams()
    params.append(this.paramValue, event.target.selectedOptions[0].value)
    params.append("target", this.kycSelectTarget.id)
    params.append("all", true); // Assuming you want to fetch all KYC records

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

  kyc_change(event) {
    if (event.target.selectedOptions[0].value) {
      let url = this.emailUrlValue;
      let param = this.emailParamValue;
      let target = this.esignEmailsOutputTarget.id; // Get the actual ID of the target element

      console.log(`event target: ${event.target}`);
      console.log(`target: ${target}`);
      console.log(`url: ${url}`);
      console.log(`param: ${param}`);

      let baseUrl = url.split("?")[0];
      let params = new URLSearchParams(url.split("?")[1]);

      params.append(param, event.target.selectedOptions[0].value);
      params.append("target", target); // Pass the actual ID of the element to be updated
      params.append("current_esign_emails_value", this.esignEmailsOutputTarget.value); // Add current value

      get(`${baseUrl}?${params}`, {
        responseKind: "turbo-stream"
      });
    }
  }
}