import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  static targets = ["kycSelect", "employeeSelect"]
  static values = {
    kycUrl: String,
    employeeUrl: String,
    param: String
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
}