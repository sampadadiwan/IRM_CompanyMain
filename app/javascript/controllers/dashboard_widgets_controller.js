import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  static targets = ["select"]
  static values = {
    url: String,
    param: String,
  }

  connect() {
    console.log(this.urlValue);
    console.log(this.paramValue);

    $("#widget_name").on('change', (event) => {
      console.log("dashboard_widgets_controller: select");
      this.change(event); 
    });
  }

  change(event) {
    console.log(this.urlValue);

    let params = new URLSearchParams();
    params.append(this.paramValue, event.target.selectedOptions[0].value);
    params.append("dashboard_name", $("#dashboard_name").val());

    get(`${this.urlValue}?${params}`, {
      responseKind: "turbo-stream"
    });
  }
}
