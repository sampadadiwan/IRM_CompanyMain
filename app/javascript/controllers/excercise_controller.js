import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cashlessfields", "calculator", "checkboxin"]
  static values = { showIf: String }

  connect() {
    console.log("Excercise controller loaded");
    this.onChange(null);
    this.checkboxinTarget.checked = false;
    this.calculatorTarget.hidden = true;
    this.cashlessfieldsTarget.hidden = true;
  }

  toggle() {
    const shares_to_sell = document.querySelector("#shares_to_sell");
    const shares_to_allot = document.querySelector("#shares_to_allot");
    console.log("toggle");
    console.log(this.checkboxinTarget.checked);
    // console.log(shares_to_sell.value);
    // console.log(shares_to_allot.value);
    if(this.checkboxinTarget.checked){
        this.calculatorTarget.hidden = false;
        this.cashlessfieldsTarget.hidden = false;
    }else if(!this.checkboxinTarget.checked){
        this.calculatorTarget.hidden = true;
        this.cashlessfieldsTarget.hidden = true;
        shares_to_sell.value = ''
        shares_to_allot.value = ''
      }

}

  onChange(event) {
    console.log("onChange");
    const outputElement = document.getElementById('calc_total_value');
    const inputElement = document.getElementById('calc_total_value_hidden');

    let qty = $("#excercise_quantity").val();
    let price = $("#excercise_price").val();

    let amount = qty * price;
    let tax_rate = $("#excercise_tax_rate").val();
    let tax = amount * tax_rate / 100.0;
    console.log("amount: " + amount);
    console.log("tax: " + tax);

    $("#excercise_amount").val(amount.toFixed(2));
    $("#excercise_amount_disabled").val(amount.toFixed(2));
    $("#excercise_tax").val(tax.toFixed(2));

    console.log(this.checkboxinTarget.checked);
    console.log($("#calc_total_value").val);
    outputElement.textContent = amount.toFixed(2);
    inputElement.value = amount.toFixed(2);
  }

}
