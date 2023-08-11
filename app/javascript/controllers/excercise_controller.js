import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cashlessfields", "calculator", "checkboxin", "paymentproof", "cashlessnote"]

  connect() {
    console.log("Excercise controller loaded");

    this.onLoad(null);
    this.checkboxinTarget.checked = false;
    this.calculatorTarget.hidden = true;
    this.cashlessfieldsTarget.hidden = true;
    this.paymentproofTarget.hidden = false;
    this.cashlessnoteTarget.hidden = true;
  }

  step1Click(){
    console.log("step1 click");
    this.calculatorTarget.hidden = true;
  }

  step2Click(){
    console.log("step2 click");
    if (this.checkboxinTarget.checked){
      this.calculatorTarget.hidden = false;
    }
  }

  step3Click(){
    console.log("step3 click");
    this.calculatorTarget.hidden = true;
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
        this.calculatorTarget.removeAttribute("hidden");
        this.cashlessfieldsTarget.hidden = false;
        this.cashlessnoteTarget.hidden = false;
        this.paymentproofTarget.hidden = true;
        shares_to_sell.value = '';
        shares_to_allot.value = '';
    }else if(!this.checkboxinTarget.checked){
        this.calculatorTarget.hidden = true;
        this.cashlessfieldsTarget.hidden = true;
        this.cashlessnoteTarget.hidden = true;
        this.paymentproofTarget.hidden = false;
        shares_to_sell.value = '';
        shares_to_allot.value = '';
      }
}

  onChange(event) {
    console.log("onChange");
    const outputElement = document.getElementById('calc_total_value');
    const inputElement = document.getElementById('calc_total_value_hidden');
    const modeElement = document.getElementById('all_or_vested_hidden');
    const quantityElement = document.getElementById('quantity_hidden');
    const calcButton = document.getElementById("calculate-btn");
    const urlParams = new URLSearchParams(window.location.search);
    const holdingId = urlParams.get('excercise[holding_id]') || urlParams.get('holding_id');
    const holdingIdElement = document.getElementById('holding_id');


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
    outputElement.textContent = amount.toFixed(2);
    inputElement.value = amount.toFixed(2);

    modeElement.value = "Custom"
    holdingIdElement.value = holdingId;
    quantityElement.value = qty;
    if(this.checkboxinTarget.checked){
      calcButton.click();
    }
  }

  onLoad(event) {
    console.log("onChange");
    const outputElement = document.getElementById('calc_total_value');
    const inputElement = document.getElementById('calc_total_value_hidden');
    const modeElement = document.getElementById('all_or_vested_hidden');
    const quantityElement = document.getElementById('quantity_hidden');
    const urlParams = new URLSearchParams(window.location.search);
    const holdingId = urlParams.get('excercise[holding_id]') || urlParams.get('holding_id');
    const holdingIdElement = document.getElementById('holding_id');


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

    outputElement.textContent = amount.toFixed(2);
    inputElement.value = amount.toFixed(2);

    modeElement.value = "Custom"
    holdingIdElement.value = holdingId;
    quantityElement.value = qty;
  }

}
