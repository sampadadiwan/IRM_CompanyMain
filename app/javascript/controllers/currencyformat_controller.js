import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    
  }

  format() {
    const input = document.querySelector("#currency");
    const [label] = input.labels;
    const formatter = new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"});

    input.addEventListener("input", e => {
      label.textContent = formatter.format(input.value)
    })
  }


}
