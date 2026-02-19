import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("call_copy connect");
    this.call_basis_changed();
  }

  copy_all(event) {
    event.preventDefault();

    // Get the closest row container
    const row = event.target.closest(".row");
    console.log("Row element:", row);

    if (!row) {
      console.warn("Could not find row container");
      return;
    }

    // Get the first price and premium values from this row
    const firstPrice = row.querySelector(".price");
    const firstPremium = row.querySelector(".premium");

    if (!firstPrice || !firstPremium) {
      console.warn("Could not find price or premium fields in first row");
      return;
    }

    const priceValue = firstPrice.value;
    const premiumValue = firstPremium.value;

    console.log(`Copying Price: ${priceValue}, Premium: ${premiumValue}`);

    // Copy price to all price fields
    if (priceValue) {
      document.querySelectorAll(".price").forEach((field) => {
        field.value = priceValue;
      });
    }

    // Copy premium to all premium fields
    if (premiumValue) {
      document.querySelectorAll(".premium").forEach((field) => {
        field.value = premiumValue;
      });
    }
  }


  copy_all_percentage_changes(e) {
    e.preventDefault();

    let percentage_change = $(".percentage_change")[0].value;
    $(".percentage_change").each(function (index, item) {
      $(item)[0].value = percentage_change;
    });
    console.log(`percentage_change = ${percentage_change}`);
  }

  call_basis_changed() {
    let call_basis = $("#capital_call_call_basis").val();
    console.log(`call_basis = ${call_basis}`);

    if (call_basis === "Percentage of Commitment") {
      $("#amount_to_be_called_group").hide();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").show();
      $("#close-percentages-container").show();
      $("#applicable-to-group").hide();
    } else if (call_basis === "Upload") {
      $("#amount_to_be_called_group").hide();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").hide();
      $("#close-percentages-container").hide();
      $("#applicable-to-group").hide();

      $(".percentage").each(function () {
        $(this).val("");
      });
    } else {
      $("#amount_to_be_called_group").show();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").hide();
      $("#close-percentages-container").hide();
      $("#applicable-to-group").show();

      $(".percentage").each(function () {
        $(this).val("");
      });
    }
  }

}
